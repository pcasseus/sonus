import 'dart:developer' as developer;

import '../../../analytics/application/services/listening_artist_attribution.dart';
import '../../domain/entities/library_organization.dart';
import '../../domain/repositories/library_organization_repository.dart';
import '../models/library_album.dart';
import '../models/project_collaborator.dart';
import '../repositories/library_query_repository.dart';

/// Why an artist is where it is in the Library.
enum ArtistPlacementReason {
  /// Its own Library entry: the artist owns at least one release.
  standalone,

  /// A contributor: the artist owns no release, so it is shown inside the
  /// projects it is credited on instead of as a Library entry.
  automatic,

  /// Placed by the user, grouped or standalone.
  manual,
}

class ArtistLibraryPlacement {
  const ArtistLibraryPlacement({
    required this.artistId,
    required this.reason,
    this.projectAlbumId,
    this.projectAlbumIds = const [],
    this.isShown = true,
  });

  final String artistId;
  final ArtistPlacementReason reason;

  /// The project the artist is mainly shown under (where it has the most
  /// songs), when it is a contributor.
  final String? projectAlbumId;

  /// Every project the contributor is credited on, main project first.
  final List<String> projectAlbumIds;

  /// Whether the artist has its own entry in the Library and Artist Search.
  final bool isShown;

  bool get isGrouped => projectAlbumId != null;
}

/// The one rule for artist identity in the Library (SN-45).
///
/// A release belongs to its owner (the album artist the importer decided,
/// such as a soundtrack's cast). An artist with at least one release of its
/// own is a **standalone** artist: it has a Library entry, appears in
/// Artist Search and artist rankings, and lists releases it is only
/// credited on under Collaborations. An artist that owns no release is a
/// **contributor**: its credits stay exactly as tagged, but it is shown
/// inside the projects it appears on, never as a catalog of its own. The
/// user can promote a contributor ("Show as its own artist") or group an
/// artist that owns nothing under a project; neither happens automatically.
///
/// Nothing here changes stored credits, songs or listening history.
class ArtistLibraryOrganization {
  const ArtistLibraryOrganization({
    required this.placements,
    required this.classifications,
    this.albumOwners = const {},
    this.catalogOwners,
  });

  /// Everything is standalone: used when the organization can't be loaded,
  /// so the Library fails open rather than hiding artists.
  static const ArtistLibraryOrganization unrestricted =
      ArtistLibraryOrganization(placements: {}, classifications: {});

  final Map<String, ArtistLibraryPlacement> placements;
  final Map<String, AlbumReleaseClassification> classifications;

  /// The owner of every release with songs, by album id.
  final Map<String, String> albumOwners;

  /// Artists that own at least one release with songs. Null means unknown,
  /// in which case every artist without a placement is standalone.
  final Set<String>? catalogOwners;

  ArtistLibraryPlacement placementOf(String artistId) {
    final placement = placements[artistId];
    if (placement != null) return placement;
    final owner = catalogOwners?.contains(artistId) ?? true;
    return ArtistLibraryPlacement(
      artistId: artistId,
      reason: owner
          ? ArtistPlacementReason.standalone
          : ArtistPlacementReason.automatic,
      isShown: owner,
    );
  }

  /// Whether the artist gets its own entry in the Library's artist list,
  /// Artist Search and artist rankings.
  bool isShownInLibrary(String artistId) => placementOf(artistId).isShown;

  /// Whether the artist owns a release of its own.
  bool ownsCatalog(String artistId) =>
      catalogOwners?.contains(artistId) ?? true;

  /// The artist a play by [artistId] on [albumId] counts for at artist
  /// level. A standalone artist keeps its own plays; a contributor's plays
  /// count for the owner of the release they are on. Every play counts for
  /// exactly one artist.
  String attributedArtistId({
    required String artistId,
    required String albumId,
  }) {
    if (isShownInLibrary(artistId)) return artistId;
    return albumOwners[albumId] ?? artistId;
  }

  /// Contributors shown under [albumId]'s collaborators.
  List<String> groupedUnder(String albumId) => [
    for (final placement in placements.values)
      if (!placement.isShown && placement.projectAlbumIds.contains(albumId))
        placement.artistId,
  ]..sort();
}

/// Why an assignment can't be made. Nothing changes when one is refused.
enum ProjectAssignmentRefusal {
  /// The artist isn't credited on the project.
  notCredited,

  /// The artist owns albums of its own; its catalog is never hidden.
  ownsAlbums,

  /// An artist can't be grouped under its own album.
  ownProject,
}

/// What "Assign to Project" would do, shown before it is done.
class ProjectAssignmentPreview {
  const ProjectAssignmentPreview({
    required this.artistId,
    required this.albumId,
    required this.songsOnProject,
    required this.songsElsewhere,
    this.refusal,
  });

  final String artistId;
  final String albumId;

  /// Songs of the project the artist is credited on.
  final int songsOnProject;

  /// Songs on other albums the artist is credited on. They stay reachable
  /// from the profile and search, but the artist leaves the Library list.
  final int songsElsewhere;

  final ProjectAssignmentRefusal? refusal;

  bool get allowed => refusal == null;
}

/// Artist identity and release organization: who is a standalone artist
/// and who is a contributor (see [ArtistLibraryOrganization]), release
/// classification, and the reversible "Assign to Project" / "Show as its
/// own artist" choices.
class LibraryOrganizationService {
  const LibraryOrganizationService({
    required this.library,
    required this.collaborators,
    required this.organization,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LibraryQueryRepository library;
  final ProjectCollaboratorQueryRepository collaborators;
  final LibraryOrganizationRepository organization;
  final DateTime Function() _now;

  Future<ArtistLibraryOrganization> load() async {
    final albums = await library.getAlbums();
    final credits = await collaborators.getProjectCollaborators();
    final classifications = {
      for (final c in await organization.getClassifications()) c.albumId: c,
    };
    final assignments = {
      for (final a in await organization.getAssignments()) a.artistId: a,
    };

    final ownerOf = {
      for (final album in albums)
        if (album.trackCount > 0) album.albumId: album.artistId,
    };
    final owners = ownerOf.values.toSet();

    // Songs per release, for every artist credited on a release it does
    // not own.
    final songsOnProject = <String, Map<String, int>>{};
    for (final credit in credits) {
      final owner = ownerOf[credit.albumId];
      if (owner == null || owner == credit.artistId) continue;
      final projects = songsOnProject.putIfAbsent(credit.artistId, () => {});
      projects[credit.albumId] =
          (projects[credit.albumId] ?? 0) + credit.songCount;
    }

    List<String> projectsOf(String artistId) {
      final projects = songsOnProject[artistId] ?? const <String, int>{};
      return projects.keys.toList()..sort((a, b) {
        final bySongs = projects[b]!.compareTo(projects[a]!);
        return bySongs != 0 ? bySongs : a.compareTo(b);
      });
    }

    final placements = <String, ArtistLibraryPlacement>{};

    for (final assignment in assignments.values) {
      final grouped = assignment.mode == ArtistProjectAssignmentMode.grouped;
      placements[assignment.artistId] = ArtistLibraryPlacement(
        artistId: assignment.artistId,
        reason: ArtistPlacementReason.manual,
        projectAlbumId: grouped ? assignment.albumId : null,
        projectAlbumIds: grouped
            ? [
                assignment.albumId!,
                for (final id in projectsOf(assignment.artistId))
                  if (id != assignment.albumId) id,
              ]
            : const [],
        isShown: !grouped,
      );
    }

    for (final artistId in songsOnProject.keys) {
      if (placements.containsKey(artistId) || owners.contains(artistId)) {
        continue;
      }
      final projects = projectsOf(artistId);
      placements[artistId] = ArtistLibraryPlacement(
        artistId: artistId,
        reason: ArtistPlacementReason.automatic,
        projectAlbumId: projects.first,
        projectAlbumIds: List.unmodifiable(projects),
        isShown: false,
      );
    }

    return ArtistLibraryOrganization(
      placements: Map.unmodifiable(placements),
      classifications: Map.unmodifiable(classifications),
      albumOwners: Map.unmodifiable(ownerOf),
      catalogOwners: Set.unmodifiable(owners),
    );
  }

  /// The project's credited performers, lead roles first.
  Future<List<ProjectCollaborator>> collaboratorsOf(String albumId) =>
      collaborators.getProjectCollaborators(albumId: albumId);

  Future<ProjectAssignmentPreview> previewAssignment({
    required String artistId,
    required String albumId,
  }) async {
    final albums = await library.getAlbums();
    final credits = (await collaborators.getProjectCollaborators()).where(
      (credit) => credit.artistId == artistId,
    );

    final onProject = credits
        .where((credit) => credit.albumId == albumId)
        .fold(0, (sum, credit) => sum + credit.songCount);
    final elsewhere = credits
        .where((credit) => credit.albumId != albumId)
        .fold(0, (sum, credit) => sum + credit.songCount);

    LibraryAlbum? project;
    for (final album in albums) {
      if (album.albumId == albumId) project = album;
    }

    final ProjectAssignmentRefusal? refusal;
    if (project?.artistId == artistId) {
      refusal = ProjectAssignmentRefusal.ownProject;
    } else if (albums.any((album) => album.artistId == artistId)) {
      refusal = ProjectAssignmentRefusal.ownsAlbums;
    } else if (onProject == 0) {
      refusal = ProjectAssignmentRefusal.notCredited;
    } else {
      refusal = null;
    }

    return ProjectAssignmentPreview(
      artistId: artistId,
      albumId: albumId,
      songsOnProject: onProject,
      songsElsewhere: elsewhere,
      refusal: refusal,
    );
  }

  /// "Assign to Project": shows the artist under [albumId]'s collaborators.
  /// Returns the preview it acted on; nothing changes if it was refused.
  Future<ProjectAssignmentPreview> assignToProject({
    required String artistId,
    required String albumId,
  }) async {
    final preview = await previewAssignment(
      artistId: artistId,
      albumId: albumId,
    );

    if (preview.allowed) {
      await _save(artistId, ArtistProjectAssignmentMode.grouped, albumId);
    }

    return preview;
  }

  /// Keeps the artist as its own Library entry, even if it would be
  /// grouped automatically.
  Future<void> showAsOwnArtist(String artistId) =>
      _save(artistId, ArtistProjectAssignmentMode.standalone, null);

  /// Undoes a manual choice; the automatic rule applies again.
  Future<void> clearAssignment(String artistId) =>
      organization.deleteAssignment(artistId);

  /// The user's classification, which replaces any external one.
  Future<void> classifyRelease({
    required String albumId,
    required ReleaseKind kind,
  }) {
    final timestamp = _now();

    return organization.saveClassification(
      AlbumReleaseClassification(
        albumId: albumId,
        kind: kind,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Future<void> clearReleaseClassification(String albumId) =>
      organization.deleteClassification(albumId);

  Future<void> _save(
    String artistId,
    ArtistProjectAssignmentMode mode,
    String? albumId,
  ) {
    final timestamp = _now();

    return organization.saveAssignment(
      ArtistProjectAssignment(
        artistId: artistId,
        mode: mode,
        albumId: albumId,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }
}

/// Artist-level statistics follow the Library's artist identity: a
/// contributor's plays count for the owner of the release they are on.
/// Fails open: if the organization can't be read, plays count for their
/// stored artist, as before.
class OrganizationArtistAttribution implements ListeningArtistAttribution {
  const OrganizationArtistAttribution(this._organization);

  final LibraryOrganizationService _organization;

  @override
  Future<ArtistAttributor> load() async {
    try {
      final organization = await _organization.load();
      return ArtistAttributor(
        (artistId, albumId) => organization.attributedArtistId(
          artistId: artistId,
          albumId: albumId,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Artist attribution could not be read (${error.runtimeType})',
        name: 'sonus.library.organization',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return ArtistAttributor.identity;
    }
  }
}
