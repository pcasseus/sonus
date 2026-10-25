import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../../domain/entities/song.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../domain/entities/album_edition.dart';

class AlbumProfileController extends ChangeNotifier {
  AlbumProfileController({
    required LibraryQueryRepository repository,
    required String albumId,
    PlaybackCoordinator? playbackCoordinator,
    AlbumProfileEditingService? albumProfileEditingService,
    AlbumEditionTrackOrderingService? albumEditionTrackOrderingService,
    SongArtistCreditRepository? songArtistCreditRepository,
    TrackProfileEditingService? trackProfileEditingService,
    SongBlockService? songBlockService,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    Random? random,
  }) : this._(
         repository,
         albumId,
         playbackCoordinator,
         albumProfileEditingService,
         albumEditionTrackOrderingService,
         songArtistCreditRepository,
         trackProfileEditingService,
         songBlockService,
         artworkAssignmentService,
         artworkFilePicker,
         random ?? Random(),
       );

  AlbumProfileController._(
    this._repository,
    this._albumId,
    this._playbackCoordinator,
    this._albumProfileEditingService,
    this._albumEditionTrackOrderingService,
    this._songArtistCreditRepository,
    this._trackProfileEditingService,
    this._songBlockService,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final String _albumId;
  final PlaybackCoordinator? _playbackCoordinator;
  final AlbumProfileEditingService? _albumProfileEditingService;
  final AlbumEditionTrackOrderingService? _albumEditionTrackOrderingService;
  final SongArtistCreditRepository? _songArtistCreditRepository;
  final TrackProfileEditingService? _trackProfileEditingService;
  final SongBlockService? _songBlockService;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final Random _random;

  LibraryAlbum? _album;
  List<LibraryAlbumEdition> _editions = const [];
  LibraryAlbumEdition? _selectedEdition;
  List<LibraryTrack> _tracks = const [];

  bool _isLoading = false;
  // Starts from the player's actual mode, which may have been restored
  // from the listener's saved preference.
  late bool _isShuffleEnabled =
      _playbackCoordinator?.currentState.shuffleEnabled ?? false;
  Object? _error;

  String get albumId => _albumId;

  LibraryAlbum? get album => _album;

  List<LibraryAlbumEdition> get editions => _editions;

  LibraryAlbumEdition? get selectedEdition => _selectedEdition;

  bool get hasEditionQueryCapability =>
      _repository is AlbumEditionQueryRepository;
  List<LibraryTrack> get tracks => _tracks;

  String? get artworkPath {
    final path = _album?.artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }

  bool canEditAlbumProfile(String? userId) {
    final primaryEditionId = _album?.primaryEditionId;

    return _albumProfileEditingService != null &&
        primaryEditionId != null &&
        primaryEditionId.trim().isNotEmpty;
  }

  Future<bool> updateProfile({
    String? userId,
    required String title,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    String? artistId,
  }) async {
    final service = _albumProfileEditingService;
    final album = _album;
    final primaryEditionId = album?.primaryEditionId;

    if (service == null ||
        album == null ||
        primaryEditionId == null ||
        primaryEditionId.trim().isEmpty) {
      return false;
    }

    await service.updateProfile(
      userId: userId,
      albumId: _albumId,
      primaryEditionId: primaryEditionId,
      title: title,
      editionTitle: editionTitle,
      editionType: editionType,
      releaseDate: releaseDate,
      genre: genre,
      artistId: artistId,
    );

    await refresh();

    return true;
  }

  bool get canEditArtwork {
    final primaryEditionId = _album?.primaryEditionId;

    return _artworkAssignmentService != null &&
        _artworkFilePicker != null &&
        primaryEditionId != null &&
        primaryEditionId.trim().isNotEmpty;
  }

  bool get canEditTrackArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  bool canEditAlbumStudio(String? userId) {
    return _albumEditionTrackOrderingService != null &&
        _selectedEdition != null &&
        _repository is AlbumEditionQueryRepository;
  }

  Future<bool> reorderSelectedEdition({
    String? userId,
    required List<String> orderedSongIds,
    bool autoRenumber = false,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository) {
      return false;
    }

    final result = await service.reorderEdition(
      albumEditionId: selectedEdition.editionId,
      orderedSongIds: orderedSongIds,
      userId: userId,
      autoRenumber: autoRenumber,
    );

    if (!result.changed) {
      return false;
    }

    await refresh();

    return true;
  }

  /// "Sort by disc & track" for the selected edition: back to automatic
  /// order. Returns false when nothing changed.
  Future<bool> sortSelectedEditionByDiscAndTrack({String? userId}) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository) {
      return false;
    }

    final result = await service.sortByDiscAndTrack(
      albumEditionId: selectedEdition.editionId,
      userId: userId,
    );

    if (!result.changed) {
      return false;
    }

    await refresh();

    return true;
  }

  Future<bool> updateSelectedEditionTrackPlacement({
    String? userId,
    required LibraryTrack track,
    required int discNumber,
    required int trackNumber,
  }) async {
    final service = _albumEditionTrackOrderingService;
    final selectedEdition = _selectedEdition;

    if (service == null ||
        selectedEdition == null ||
        _repository is! AlbumEditionQueryRepository ||
        track.albumEditionId != selectedEdition.editionId) {
      return false;
    }

    final result = await service.updateTrackPlacement(
      userId: userId,
      albumEditionId: selectedEdition.editionId,
      songId: track.songId,
      discNumber: discNumber,
      trackNumber: trackNumber,
    );

    if (!result.changed) {
      return false;
    }

    await refresh();

    return true;
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

  Future<bool> changeArtwork() async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;
    final primaryEditionId = _album?.primaryEditionId;

    if (service == null ||
        picker == null ||
        primaryEditionId == null ||
        primaryEditionId.trim().isEmpty) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignAlbumEdition(
      albumEditionId: primaryEditionId,
      filePath: filePath,
    );

    await refresh();

    return true;
  }

  Future<bool> clearArtwork() async {
    final service = _artworkAssignmentService;
    final primaryEditionId = _album?.primaryEditionId;

    if (service == null ||
        primaryEditionId == null ||
        primaryEditionId.trim().isEmpty) {
      return false;
    }

    await service.clearAlbumEdition(primaryEditionId);

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

  bool get isLoading => _isLoading;

  bool get isShuffleEnabled => _isShuffleEnabled;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isNotFound {
    return !_isLoading && _error == null && _album == null;
  }

  bool get hasPlayableTracks {
    return _tracks.any(_isPlayable);
  }

  int get totalDurationSeconds {
    var total = 0;

    for (final track in _tracks) {
      if (track.durationSeconds > 0) {
        total += track.durationSeconds;
      }
    }

    return total;
  }

  Duration get totalDuration {
    return Duration(seconds: totalDurationSeconds);
  }

  int get playableTrackCount {
    var count = 0;

    for (final track in _tracks) {
      if (_isPlayable(track)) {
        count++;
      }
    }

    return count;
  }

  int get unavailableTrackCount {
    return _tracks.where((track) => !_isAvailable(track)).length;
  }

  bool get hasUnavailableTracks {
    return unavailableTrackCount > 0;
  }

  int get editionCount {
    if (_editions.isNotEmpty) {
      return _editions.length;
    }

    return _tracks.map((track) => track.albumEditionId).toSet().length;
  }

  bool get hasMultipleEditions {
    return editionCount > 1;
  }

  List<String> get editionTitles {
    if (_editions.isNotEmpty) {
      return List<String>.unmodifiable(
        _editions
            .map((edition) => edition.title.trim())
            .where((title) => title.isNotEmpty),
      );
    }

    final editionIds = <String>{};
    final titles = <String>[];

    for (final track in _tracks) {
      if (!editionIds.add(track.albumEditionId)) {
        continue;
      }

      final title = track.albumEditionTitle.trim();

      if (title.isNotEmpty) {
        titles.add(title);
      }
    }

    return List<String>.unmodifiable(titles);
  }

  Future<void> load() async {
    final preferredEditionId = _selectedEdition?.editionId;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final album = await _repository.getAlbumById(_albumId);

      if (album == null) {
        _album = null;
        _editions = const [];
        _selectedEdition = null;
        _tracks = const [];
        return;
      }

      final Object repository = _repository;

      if (repository is AlbumEditionQueryRepository) {
        final editions = await repository.getAlbumEditions(_albumId);

        if (editions.isNotEmpty) {
          final selectedEdition = _chooseEdition(
            editions,
            preferredEditionId: preferredEditionId,
            primaryEditionId: album.primaryEditionId,
          );

          final tracks = await repository.getTracksByAlbumEditionId(
            selectedEdition.editionId,
          );

          _album = album;
          _editions = editions;
          _selectedEdition = selectedEdition;
          _tracks = tracks;
          return;
        }
      }

      final tracks = await _repository.getTracksByAlbumId(_albumId);

      _album = album;
      _editions = const [];
      _selectedEdition = null;
      _tracks = tracks;
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() {
    return load();
  }

  Future<bool> selectEdition(String editionId) async {
    final Object repository = _repository;

    if (repository is! AlbumEditionQueryRepository) {
      return false;
    }

    final normalizedEditionId = editionId.trim();

    if (normalizedEditionId.isEmpty) {
      return false;
    }

    LibraryAlbumEdition? edition;

    for (final candidate in _editions) {
      if (candidate.editionId == normalizedEditionId) {
        edition = candidate;
        break;
      }
    }

    if (edition == null) {
      return false;
    }

    if (_selectedEdition?.editionId == edition.editionId) {
      return true;
    }

    try {
      final tracks = await repository.getTracksByAlbumEditionId(
        edition.editionId,
      );

      _selectedEdition = edition;
      _tracks = tracks;
      notifyListeners();

      return true;
    } catch (_) {
      return false;
    }
  }

  LibraryAlbumEdition _chooseEdition(
    List<LibraryAlbumEdition> editions, {
    String? preferredEditionId,
    String? primaryEditionId,
  }) {
    final normalizedPreferredEditionId = preferredEditionId?.trim();

    if (normalizedPreferredEditionId != null &&
        normalizedPreferredEditionId.isNotEmpty) {
      for (final edition in editions) {
        if (edition.editionId == normalizedPreferredEditionId) {
          return edition;
        }
      }
    }

    final normalizedPrimaryEditionId = primaryEditionId?.trim();

    if (normalizedPrimaryEditionId != null &&
        normalizedPrimaryEditionId.isNotEmpty) {
      for (final edition in editions) {
        if (edition.editionId == normalizedPrimaryEditionId) {
          return edition;
        }
      }
    }

    for (final edition in editions) {
      if (edition.isPrimary) {
        return edition;
      }
    }

    return editions.first;
  }

  Future<void> playTrack(LibraryTrack track) async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || !_isPlayable(track)) {
      return;
    }

    final startIndex = _tracks.indexWhere(
      (candidate) => candidate.songId == track.songId,
    );

    if (startIndex == -1) {
      await playbackCoordinator.playTrack(track);
      return;
    }

    await playbackCoordinator.playTracks(_tracks, startIndex: startIndex);
  }

  Future<void> playAll() async {
    final playbackCoordinator = _playbackCoordinator;

    if (playbackCoordinator == null || _tracks.isEmpty) {
      return;
    }

    final playableIndexes = <int>[];

    for (var index = 0; index < _tracks.length; index++) {
      if (_isPlayable(_tracks[index])) {
        playableIndexes.add(index);
      }
    }

    if (playableIndexes.isEmpty) {
      return;
    }

    final startIndex = _isShuffleEnabled
        ? playableIndexes[_random.nextInt(playableIndexes.length)]
        : playableIndexes.first;

    await playbackCoordinator.playTracks(_tracks, startIndex: startIndex);
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

  bool _isAvailable(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  bool _isPlayable(LibraryTrack track) {
    return !track.isBlocked && _isAvailable(track);
  }
}
