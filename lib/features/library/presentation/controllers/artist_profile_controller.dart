import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sonus_next/core/identity/text_normalizer.dart';

import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
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

  /// What Play and Shuffle queue: the artist's own songs, then the other
  /// performers' songs on the artist's own albums.
  List<LibraryTrack> get playbackTracks => [..._tracks, ..._projectTracks];

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

      final artistsById = projectTracks.isEmpty
          ? const <String, LibraryArtist>{}
          : {
              for (final candidate in await _repository.getArtists())
                candidate.artistId: candidate,
            };

      _artist = artist;
      _albums = albums;
      _tracks = tracks;
      _featuredTracks = featuredTracks;
      _projectTracks = projectTracks;
      _allTracks = [...tracks, ...featuredTracks, ...projectTracks];
      _collaborationTracks = ArtistProfileSections.collaborations(
        mainTracks: tracks,
        featuredTracks: featuredTracks,
        ownedAlbumIds: ownedAlbumIds,
      );
      _collaborators = ArtistProfileSections.collaborators(
        projectArtistId: _artistId,
        projectTracks: projectTracks,
        artistsById: artistsById,
      );
      _topTracks = await _rankTopTracks();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Re-reads the all-time ranking only, for example after returning from
  /// another page where songs may have been played.
  Future<void> refreshTopTracks() async {
    if (_artist == null) return;

    final topTracks = await _rankTopTracks();
    if (_sameTopTracks(topTracks, _topTracks)) return;

    _topTracks = topTracks;
    notifyListeners();
  }

  Future<List<ArtistTopTrack>> _rankTopTracks() async {
    final qualifiedPlays = _qualifiedPlays;
    final catalogue = playbackTracks;

    if (qualifiedPlays == null || catalogue.isEmpty) return const [];

    try {
      final rankings = await AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
      ).load(period: AnalyticsPeriod.lifetime, referenceLocal: _clock());

      return ArtistProfileSections.topTracks(
        catalogue: catalogue,
        rankedSongs: rankings.songs,
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
      return const [];
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
