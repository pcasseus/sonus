import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sonus_next/core/identity/text_normalizer.dart';

import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_crop_service.dart';
import '../../../artwork/domain/entities/artwork_crop.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/project_collaborator.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/library_organization_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/entities/library_organization.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../domain/entities/song.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../models/artist_profile_sections.dart';

class ArtistProfileController extends ChangeNotifier {
  ArtistProfileController({
    required LibraryQueryRepository repository,
    required String artistId,
    PlaybackCoordinator? playbackCoordinator,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    ArtistProfileEditingService? artistProfileEditingService,
    SongBlockService? songBlockService,
    SongArtistCreditRepository? songArtistCreditRepository,
    TrackProfileEditingService? trackProfileEditingService,
    QualifiedPlayRepository? qualifiedPlays,
    ArtworkCropService? artworkCropService,
    LibraryOrganizationService? organization,
    String? projectArtistId,
    DateTime Function()? clock,
    Random? random,
  }) : this._(
         repository,
         artistId,
         playbackCoordinator,
         artworkAssignmentService,
         artworkFilePicker,
         artistProfileEditingService,
         songBlockService,
         songArtistCreditRepository,
         trackProfileEditingService,
         qualifiedPlays,
         artworkCropService,
         organization,
         projectArtistId,
         clock ?? DateTime.now,
         random ?? Random(),
       );

  ArtistProfileController._(
    this._repository,
    this._artistId,
    this._playbackCoordinator,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._artistProfileEditingService,
    this._songBlockService,
    this._songArtistCreditRepository,
    this._trackProfileEditingService,
    this._qualifiedPlays,
    this._artworkCropService,
    this._organizationService,
    this._projectArtistId,
    this._clock,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final String _artistId;
  final PlaybackCoordinator? _playbackCoordinator;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final ArtistProfileEditingService? _artistProfileEditingService;
  final SongBlockService? _songBlockService;
  final SongArtistCreditRepository? _songArtistCreditRepository;
  final TrackProfileEditingService? _trackProfileEditingService;
  final QualifiedPlayRepository? _qualifiedPlays;
  final ArtworkCropService? _artworkCropService;

  /// The Library's artist identity. Without it every artist is shown as a
  /// standalone artist.
  final LibraryOrganizationService? _organizationService;

  /// The project this profile was opened from, for a contributor: only
  /// their songs there are shown.
  final String? _projectArtistId;
  final DateTime Function() _clock;
  final Random _random;

  LibraryArtist? _artist;
  List<LibraryAlbum> _albums = const [];
  List<LibraryTrack> _tracks = const [];
  List<LibraryTrack> _allTracks = const [];
  List<LibraryTrack> _featuredTracks = const [];
  List<LibraryTrack> _projectTracks = const [];
  List<LibraryTrack> _collaborationTracks = const [];
  List<ArtistProfileCollaborator> _collaborators = const [];
  List<ArtistTopTrack> _topTracks = const [];
  ArtistStanding? _standing;
  ArtistLibraryOrganization? _organization;
  List<ContributorAppearance> _appearances = const [];

  bool _isLoading = false;
  // Starts from the player's actual mode, which may have been restored
  // from the listener's saved preference.
  late bool _isShuffleEnabled =
      _playbackCoordinator?.currentState.shuffleEnabled ?? false;
  Object? _error;

  String get artistId => _artistId;

  LibraryArtist? get artist => _artist;

  List<LibraryAlbum> get albums => _albums;

  List<LibraryTrack> get tracks => _tracks;

  List<LibraryTrack> get allTracks => _allTracks;

  List<LibraryTrack> get featuredTracks => _featuredTracks;

  /// Tracks on albums this artist owns that another artist performs, such
  /// as the songs of a soundtrack or cast project.
  List<LibraryTrack> get projectTracks => _projectTracks;

  /// Featured and guest credits, plus main credits on releases owned by
  /// another artist.
  List<LibraryTrack> get collaborationTracks => _collaborationTracks;

  /// The other lead artists on this artist's albums, once each.
  List<ArtistProfileCollaborator> get collaborators => _collaborators;

  /// Up to five of the catalogue's most streamed songs, all-time.
  List<ArtistTopTrack> get topTracks => _topTracks;

  /// The artist's place in the listener's all-time artist ranking.
  ArtistStanding? get standing => _standing;

  /// Whether this artist is a contributor: it owns no release, so its page
  /// shows where it appears instead of a catalog of its own.
  bool get isContributor =>
      _artist != null &&
      _organization != null &&
      !_organization!.isShownInLibrary(_artistId);

  /// For a contributor, the projects it appears on with its songs there
  /// (only [projectArtistId]'s, when the page was opened from it).
  List<ContributorAppearance> get appearances => _appearances;

  /// Performers of Top Tracks whose artist-level streams count for another
  /// artist than this one, such as an independent artist's song on this
  /// soundtrack. Their song counts are unchanged; only the artist total in
  /// the header leaves them out.
  List<String> get topTracksCountedElsewhere {
    final organization = _organization;
    if (organization == null) return const [];
    final names = <String>[];
    for (final entry in _topTracks) {
      final track = entry.track;
      final countsFor = organization.attributedArtistId(
        artistId: track.artistId,
        albumId: track.albumId,
      );
      if (countsFor != _artistId && !names.contains(track.artistName)) {
        names.add(track.artistName);
      }
    }
    return List.unmodifiable(names);
  }

  /// The project this page was opened from, if any.
  String? get projectArtistId => _projectArtistId;

  /// The release's format: as stated, null while it needs review (it might
  /// be a Single), otherwise an Album.
  ReleaseFormat? formatOf(String albumId) {
    final organization = _organization;
    return organization == null
        ? ReleaseFormat.album
        : organization.formatOf(albumId);
  }

  /// The wide banner photo, exactly as saved.
  String? get bannerPath => _nonEmpty(_artist?.headerArtworkPath);

  /// The smaller identity photo, exactly as saved. Never the banner: a
  /// missing portrait shows initials instead.
  String? get portraitPath => _nonEmpty(_artist?.topArtistsArtworkPath);

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// What Play and Shuffle queue: the artist's own songs, then the other
  /// performers' songs on the artist's own albums.
  /// For a contributor, its songs on the projects shown.
  List<LibraryTrack> get playbackTracks => isContributor
      ? [for (final appearance in _appearances) ...appearance.tracks]
      : [..._tracks, ..._projectTracks];

  String? get headerArtworkPath {
    final path = _artist?.headerArtworkPath?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }

  String? get topArtistsArtworkPath {
    final topArtistsPath = _artist?.topArtistsArtworkPath?.trim();

    if (topArtistsPath != null && topArtistsPath.isNotEmpty) {
      return topArtistsPath;
    }

    return headerArtworkPath;
  }

  bool get isLoading => _isLoading;

  bool get isShuffleEnabled => _isShuffleEnabled;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isNotFound {
    return !_isLoading && _error == null && _artist == null;
  }

  bool get hasPlayableTracks {
    return playbackTracks.any(_isPlayable);
  }

  bool get canEditArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  bool get canEditTrackArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  Future<List<SongArtistCredit>> getTrackAdditionalCredits(
    String songId,
  ) async {
    final repository = _songArtistCreditRepository;

    if (repository == null) {
      return const [];
    }

    final credits = await repository.getBySongId(songId);

    final additionalCredits =
        credits
            .where((credit) => credit.role != SongArtistCreditRole.primary)
            .toList(growable: false)
          ..sort((a, b) => a.position.compareTo(b.position));

    return List<SongArtistCredit>.unmodifiable(additionalCredits);
  }

  bool canEditTrack(String? userId) {
    return _trackProfileEditingService != null;
  }

  Future<bool> updateTrack({
    String? userId,
    required LibraryTrack track,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
  }) async {
    final service = _trackProfileEditingService;

    if (service == null) {
      return false;
    }

    await service.updateTrack(
      userId: userId,
      songId: track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      featuredArtists: featuredArtists,
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
    );

    await refresh();

    return true;
  }

  Future<bool> updateTrackWithCredits({
    String? userId,
    required LibraryTrack track,
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    String? versionLabel,
    List<SongVersionCharacteristic> versionCharacteristics = const [],
    SongReleaseStatus releaseStatus = SongReleaseStatus.released,
    bool isLeak = false,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    String? placementEditionId,
  }) async {
    final service = _trackProfileEditingService;

    if (service == null) {
      return false;
    }

    await service.updateTrackWithCredits(
      userId: userId,
      songId: track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      additionalCredits: additionalCredits,
      isSingle: isSingle,
      versionLabel: versionLabel,
      versionCharacteristics: versionCharacteristics,
      releaseStatus: releaseStatus,
      isLeak: isLeak,
      updateVersionMetadata: true,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      placementEditionId: placementEditionId,
    );

    await refresh();

    return true;
  }

  bool canEditArtist(String? userId) {
    return _artistProfileEditingService != null;
  }

  bool canRemoveArtist(String? userId) {
    return canEditArtist(userId) && _artist != null;
  }

  Future<bool> removeArtist({String? userId}) async {
    final service = _artistProfileEditingService;

    if (service == null || _artist == null) {
      return false;
    }

    await service.removeArtist(userId: userId, artistId: _artistId);

    return true;
  }

  bool canSetTrackBlocked(String? userId) {
    return _songBlockService != null;
  }

  Future<bool> setTrackBlocked({
    String? userId,
    required LibraryTrack track,
    required bool isBlocked,
  }) async {
    final service = _songBlockService;

    if (service == null) {
      return false;
    }

    final normalizedUserId = userId?.trim();

    await service.setBlocked(
      userId: normalizedUserId == null || normalizedUserId.isEmpty
          ? null
          : normalizedUserId,
      songId: track.songId,
      isBlocked: isBlocked,
    );

    if (isBlocked) {
      final playbackCoordinator = _playbackCoordinator;

      if (playbackCoordinator != null) {
        await playbackCoordinator.removeBlockedSongFromQueue(track.songId);
      }
    }

    await refresh();

    return true;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final structuredRepository =
          _repository is StructuredArtistQueryRepository
          ? _repository as StructuredArtistQueryRepository
          : null;

      final eligibleArtist = structuredRepository != null
          ? await structuredRepository.getProfileEligibleArtistById(_artistId)
          : await _repository.getArtistById(_artistId);

      // An artist who only owns albums (a soundtrack or cast project) has no
      // main credit, so the eligibility query does not return it. Owning an
      // album is a structured relationship, so its existing record is used.
      final albums = eligibleArtist != null || structuredRepository != null
          ? await _repository.getAlbumsByArtistId(_artistId)
          : const <LibraryAlbum>[];
      final artist =
          eligibleArtist ??
          (albums.isNotEmpty
              ? await _repository.getArtistById(_artistId)
              : null);

      if (artist == null) {
        _artist = null;
        _albums = const [];
        _tracks = const [];
        _allTracks = const [];
        _featuredTracks = const [];
        _projectTracks = const [];
        _collaborationTracks = const [];
        _collaborators = const [];
        _topTracks = const [];
        _standing = null;
        _appearances = const [];
        return;
      }

      final ownedAlbumIds = {for (final album in albums) album.albumId};

      final List<LibraryTrack> tracks;
      final List<LibraryTrack> featuredTracks;
      final List<LibraryTrack> catalogTracks;

      if (structuredRepository != null) {
        tracks = await structuredRepository.getMainTracksByArtistId(_artistId);

        featuredTracks = await structuredRepository
            .getCollaborationTracksByArtistId(_artistId);

        catalogTracks = ownedAlbumIds.isEmpty
            ? const []
            : await _repository.getTracks();
      } else {
        tracks = await _repository.getTracksByArtistId(_artistId);

        final allCatalogTracks = await _repository.getTracks();

        catalogTracks = allCatalogTracks.isEmpty && tracks.isNotEmpty
            ? tracks
            : allCatalogTracks;

        final canonicalArtistName = TextNormalizer.canonicalize(artist.name);

        featuredTracks = catalogTracks
            .where(
              (track) =>
                  track.artistId != _artistId &&
                  track.featuredArtists.any(
                    (featuredArtist) =>
                        TextNormalizer.canonicalize(featuredArtist) ==
                        canonicalArtistName,
                  ),
            )
            .toList(growable: false);
      }

      final ownSongIds = {
        for (final track in [...tracks, ...featuredTracks]) track.songId,
      };
      final projectTracks = catalogTracks
          .where(
            (track) =>
                ownedAlbumIds.contains(track.albumId) &&
                track.artistId != _artistId &&
                !ownSongIds.contains(track.songId),
          )
          .toList(growable: false);

      // Structured credits (any role) when the repository has them; the
      // songs' lead artists otherwise.
      final credits = await _projectCredits(ownedAlbumIds);

      final artistsById = projectTracks.isEmpty && (credits?.isEmpty ?? true)
          ? const <String, LibraryArtist>{}
          : {
              for (final candidate in await _repository.getArtists())
                candidate.artistId: candidate,
            };

      final organization = await _loadOrganization();
      final collaborationAlbums = {
        for (final album in await _repository.getAlbums()) album.albumId: album,
      };

      _organization = organization;
      _artist = artist;
      _albums = [...albums]..sort(ArtistProfileSections.compareReleases);
      _tracks = tracks;
      _featuredTracks = featuredTracks;
      _projectTracks = projectTracks;
      _allTracks = [...tracks, ...featuredTracks, ...projectTracks];
      _collaborationTracks = ArtistProfileSections.collaborations(
        mainTracks: tracks,
        featuredTracks: featuredTracks,
        ownedAlbumIds: ownedAlbumIds,
        albumsById: collaborationAlbums,
      );
      _appearances =
          organization != null && !organization.isShownInLibrary(_artistId)
          ? ArtistProfileSections.appearances(
              tracks: [...tracks, ...featuredTracks],
              albumsById: collaborationAlbums,
              projectArtistId: _projectArtistId,
            )
          : const [];
      _collaborators = credits == null
          ? ArtistProfileSections.collaborators(
              projectArtistId: _artistId,
              projectTracks: projectTracks,
              artistsById: artistsById,
            )
          : ArtistProfileSections.structuredCollaborators(
              projectArtistId: _artistId,
              credits: credits,
              projectTracks: projectTracks,
              artistsById: artistsById,
            );
      await _loadRankings();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Fails open: if the organization can't be read, the artist is shown as
  /// a standalone artist.
  Future<ArtistLibraryOrganization?> _loadOrganization() async {
    try {
      return await _organizationService?.load();
    } catch (error, stackTrace) {
      developer.log(
        'Library organization could not be read (${error.runtimeType})',
        name: 'sonus.library.artist_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Credited performers of the artist's own albums, or null when the
  /// repository has no structured credit query (or it fails, in which
  /// case the lead-artist list is shown instead).
  Future<List<ProjectCollaborator>?> _projectCredits(
    Set<String> ownedAlbumIds,
  ) async {
    final Object repository = _repository;
    if (repository is! ProjectCollaboratorQueryRepository) return null;
    if (ownedAlbumIds.isEmpty) return const [];

    try {
      return [
        for (final albumId in ownedAlbumIds)
          ...await repository.getProjectCollaborators(albumId: albumId),
      ];
    } catch (error, stackTrace) {
      developer.log(
        'Project credits could not be read (${error.runtimeType})',
        name: 'sonus.library.artist_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Re-reads the all-time ranking only, for example after returning from
  /// another page where songs may have been played.
  Future<void> refreshTopTracks() async {
    if (_artist == null) return;

    final previousTopTracks = _topTracks;
    final previousStanding = _standing;
    await _loadRankings();
    if (_sameTopTracks(previousTopTracks, _topTracks) &&
        previousStanding == _standing) {
      return;
    }

    notifyListeners();
  }

  Future<void> _loadRankings() async {
    final qualifiedPlays = _qualifiedPlays;
    final catalogue = playbackTracks;

    if (qualifiedPlays == null) {
      _topTracks = const [];
      _standing = null;
      return;
    }

    try {
      final organizationService = _organizationService;
      final rankings = await AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: organizationService == null
            ? null
            : OrganizationArtistAttribution(organizationService),
      ).load(period: AnalyticsPeriod.lifetime, referenceLocal: _clock());

      _topTracks = ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: rankings.songs,
      );
      _standing = ArtistProfileSections.standing(
        artistId: _artistId,
        rankedArtists: rankings.artists,
      );
    } catch (error, stackTrace) {
      // Top Tracks is optional; the rest of the profile still shows.
      developer.log(
        'Could not rank top tracks (${error.runtimeType})',
        name: 'sonus.library.artist_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _topTracks = const [];
      _standing = null;
    }
  }

  static bool _sameTopTracks(List<ArtistTopTrack> a, List<ArtistTopTrack> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!identical(a[index].track, b[index].track) ||
          a[index].streamCount != b[index].streamCount) {
        return false;
      }
    }
    return true;
  }

  Future<bool> renameArtist({String? userId, required String name}) async {
    final service = _artistProfileEditingService;

    if (service == null) {
      return false;
    }

    await service.renameArtist(userId: userId, artistId: _artistId, name: name);

    await refresh();

    return true;
  }

  /// Plays a Top Tracks song with the Top Tracks list as its queue.
  Future<void> playTopTrack(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    await playbackCoordinator.playInContext(track, [
      for (final entry in _topTracks) entry.track,
    ]);
  }

  bool get canCropArtwork => _artworkCropService != null && canEditArtwork;

  Future<String?> pickArtworkFile() async =>
      _artworkFilePicker?.pickArtworkFile();

  Future<bool> applyArtworkCrop({
    required ArtworkCropTarget target,
    required String sourcePath,
    required CropRect rect,
    String? userId,
  }) async {
    final service = _artworkCropService;
    if (service == null) return false;

    await service.apply(
      target: target,
      targetId: _artistId,
      sourcePath: sourcePath,
      rect: rect,
      userId: userId,
    );
    await refresh();
    return true;
  }

  Future<ArtworkCropSource?> artworkRepositionSource(
    ArtworkCropTarget target,
  ) async {
    final service = _artworkCropService;
    final artist = _artist;
    if (service == null || artist == null) return null;

    final (id, path) = _artworkOf(target, artist);
    if (path == null) return null;

    return service.repositionSource(
      target: target,
      targetId: _artistId,
      currentArtworkId: id,
      currentArtworkPath: path,
    );
  }

  Future<bool> resetArtworkCrop(
    ArtworkCropTarget target, {
    String? userId,
  }) async {
    final service = _artworkCropService;
    final artist = _artist;
    if (service == null || artist == null) return false;

    final reset = await service.reset(
      target: target,
      targetId: _artistId,
      currentArtworkId: _artworkOf(target, artist).$1,
      userId: userId,
    );
    if (reset) await refresh();
    return reset;
  }

  static (String?, String?) _artworkOf(
    ArtworkCropTarget target,
    LibraryArtist artist,
  ) => switch (target) {
    ArtworkCropTarget.artistBanner => (
      artist.headerArtworkId,
      _nonEmpty(artist.headerArtworkPath),
    ),
    ArtworkCropTarget.artistPortrait => (
      artist.topArtistsArtworkId,
      _nonEmpty(artist.topArtistsArtworkPath),
    ),
    ArtworkCropTarget.albumEdition => (null, null),
  };

  Future<bool> changeHeaderArtwork({String? userId}) async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (service == null || picker == null) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignArtistHeader(
      artistId: _artistId,
      filePath: filePath,
      userId: userId,
    );

    await refresh();

    return true;
  }

  Future<bool> clearHeaderArtwork({String? userId}) async {
    final service = _artworkAssignmentService;

    if (service == null) {
      return false;
    }

    await service.clearArtistHeader(_artistId, userId: userId);

    await refresh();

    return true;
  }

  Future<bool> changeTopArtistsArtwork({String? userId}) async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (service == null || picker == null) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignArtistTopArtists(
      artistId: _artistId,
      filePath: filePath,
      userId: userId,
    );

    await refresh();

    return true;
  }

  Future<bool> clearTopArtistsArtwork({String? userId}) async {
    final service = _artworkAssignmentService;

    if (service == null) {
      return false;
    }

    await service.clearArtistTopArtists(_artistId, userId: userId);

    await refresh();

    return true;
  }

  Future<bool> changeTrackArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;
    final songId = track.songId.trim();

    if (service == null || picker == null || songId.isEmpty) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignSong(songId: songId, filePath: filePath);

    await refresh();

    return true;
  }

  Future<bool> clearTrackArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;
    final songId = track.songId.trim();

    if (service == null || songId.isEmpty) {
      return false;
    }

    await service.clearSong(songId);

    await refresh();

    return true;
  }

  Future<void> playTrack(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    final queue = playbackTracks;
    final startIndex = queue.indexWhere(
      (candidate) => candidate.songId == track.songId,
    );

    if (startIndex == -1) {
      await playbackCoordinator.playTrack(track);
      return;
    }

    await playbackCoordinator.playTracks(queue, startIndex: startIndex);
  }

  Future<void> playAll() async {
    final playbackCoordinator = _playbackCoordinator;

    final queue = playbackTracks;

    if (playbackCoordinator == null || queue.isEmpty) {
      return;
    }

    final playableIndexes = <int>[];

    for (var index = 0; index < queue.length; index++) {
      if (_isPlayable(queue[index])) {
        playableIndexes.add(index);
      }
    }

    if (playableIndexes.isEmpty) {
      return;
    }

    final startIndex = _isShuffleEnabled
        ? playableIndexes[_random.nextInt(playableIndexes.length)]
        : playableIndexes.first;

    await playbackCoordinator.playTracks(queue, startIndex: startIndex);
  }

  /// Plays one collaborator's songs on this artist's projects.
  Future<void> playCollaborator(ArtistProfileCollaborator collaborator) async {
    final playbackCoordinator = _playbackCoordinator;
    final first = collaborator.tracks.indexWhere(_isPlayable);

    if (playbackCoordinator == null || first == -1) {
      return;
    }

    await playbackCoordinator.playTracks(
      collaborator.tracks,
      startIndex: first,
    );
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    if (_isShuffleEnabled == enabled) {
      return;
    }

    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null) {
      return;
    }

    await playbackCoordinator.setShuffleEnabled(enabled);

    _isShuffleEnabled = enabled;
    notifyListeners();
  }

  Future<void> toggleShuffle() {
    return setShuffleEnabled(!_isShuffleEnabled);
  }

  Future<void> playNext(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    await playbackCoordinator.playNext(track);
  }

  Future<void> addToQueue(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    await playbackCoordinator.addToQueue(track);
  }

  bool isTrackPlayable(LibraryTrack track) {
    return _isPlayable(track);
  }

  bool _isPlayable(LibraryTrack track) {
    return !track.isBlocked &&
        track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }
}
