import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/entities/album_edition.dart';

class AlbumProfileController extends ChangeNotifier {
  AlbumProfileController({
    required LibraryQueryRepository repository,
    required String albumId,
    PlaybackCoordinator? playbackCoordinator,
    AlbumProfileEditingService? albumProfileEditingService,
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
  final TrackProfileEditingService? _trackProfileEditingService;
  final SongBlockService? _songBlockService;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final Random _random;

  LibraryAlbum? _album;
  List<LibraryTrack> _tracks = const [];

  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  Object? _error;

  String get albumId => _albumId;

  LibraryAlbum? get album => _album;

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
        userId != null &&
        userId.trim().isNotEmpty &&
        primaryEditionId != null &&
        primaryEditionId.trim().isNotEmpty;
  }

  Future<bool> updateProfile({
    required String userId,
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
        userId.trim().isEmpty ||
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

  bool canEditTrack(String? userId) {
    return _trackProfileEditingService != null &&
        userId != null &&
        userId.trim().isNotEmpty;
  }

  Future<bool> updateTrack({
    required String userId,
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

    if (service == null || userId.trim().isEmpty) {
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
    return _tracks.map((track) => track.albumEditionId).toSet().length;
  }

  bool get hasMultipleEditions {
    return editionCount > 1;
  }

  List<String> get editionTitles {
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final album = await _repository.getAlbumById(_albumId);

      if (album == null) {
        _album = null;
        _tracks = const [];
        return;
      }

      final tracks = await _repository.getTracksByAlbumId(_albumId);

      _album = album;
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
