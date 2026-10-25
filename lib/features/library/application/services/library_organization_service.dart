import '../../domain/entities/library_organization.dart';
import '../../domain/repositories/library_organization_repository.dart';
import '../models/library_album.dart';
import '../models/project_collaborator.dart';
import '../repositories/library_query_repository.dart';

/// Why an artist is where it is in the Library.
enum ArtistPlacementReason {
  /// Its own Library entry: the default.
  standalone,

  /// Grouped automatically: every credit is on one soundtrack or cast
  /// recording owned by someone else, and the artist owns no albums.
  automatic,

  /// Placed by the user, grouped or standalone.
  manual,
}

class ArtistLibraryPlacement {
  const ArtistLibraryPlacement({
    required this.artistId,
    required this.reason,
    this.projectAlbumId,
  });

  final String artistId;
  final ArtistPlacementReason reason;

  /// The project the artist is shown under, when grouped.
  final String? projectAlbumId;

  bool get isGrouped => projectAlbumId != null;
}

/// Where every artist appears. Artists missing from [placements] are
/// standalone. Grouping only moves an artist's Library entry under its
/// project: credits, search results and profiles are unchanged.
class ArtistLibraryOrganization {
  const ArtistLibraryOrganization({
    required this.placements,
    required this.classifications,
  });

  final Map<String, ArtistLibraryPlacement> placements;
  final Map<String, AlbumReleaseClassification> classifications;

  ArtistLibraryPlacement placementOf(String artistId) =>
      placements[artistId] ??
      ArtistLibraryPlacement(
        artistId: artistId,
        reason: ArtistPlacementReason.standalone,
      );

  /// Whether the artist gets its own entry in the Library's artist list.
  bool isShownInLibrary(String artistId) => !placementOf(artistId).isGrouped;

  /// Artists shown under [albumId]'s collaborators instead of the Library.
  List<String> groupedUnder(String albumId) => [
    for (final placement in placements.values)
      if (placement.projectAlbumId == albumId) placement.artistId,
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

/// Soundtrack and collaborator organization: release classification,
/// automatic grouping of soundtrack-only performers, and the reversible
/// "Assign to Project" / "Show as its own artist" choices.
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

    final ownerOf = {for (final album in albums) album.albumId: album.artistId};
    final owners = ownerOf.values.toSet();
    final projectsOf = <String, Set<String>>{};

    for (final credit in credits) {
      projectsOf.putIfAbsent(credit.artistId, () => {}).add(credit.albumId);
    }

    final placements = <String, ArtistLibraryPlacement>{};

    for (final assignment in assignments.values) {
      placements[assignment.artistId] = ArtistLibraryPlacement(
        artistId: assignment.artistId,
        reason: ArtistPlacementReason.manual,
        projectAlbumId: assignment.mode == ArtistProjectAssignmentMode.grouped
            ? assignment.albumId
            : null,
      );
    }

    for (final MapEntry(key: artistId, value: projects) in projectsOf.entries) {
      if (placements.containsKey(artistId) ||
          owners.contains(artistId) ||
          projects.length != 1) {
        continue;
      }

      final project = projects.single;
      final classification = classifications[project];

      if (classification != null &&
          classification.groupsPerformers &&
          ownerOf[project] != artistId) {
        placements[artistId] = ArtistLibraryPlacement(
          artistId: artistId,
          reason: ArtistPlacementReason.automatic,
          projectAlbumId: project,
        );
      }
    }

    return ArtistLibraryOrganization(
      placements: Map.unmodifiable(placements),
      classifications: Map.unmodifiable(classifications),
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
