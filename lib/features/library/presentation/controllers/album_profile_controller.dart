import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';

class AlbumProfileController extends ChangeNotifier {
  AlbumProfileController({
    required LibraryQueryRepository repository,
    required String albumId,
    PlaybackCoordinator? playbackCoordinator,
    Random? random,
  }) : this._(repository, albumId, playbackCoordinator, random ?? Random());

  AlbumProfileController._(
    this._repository,
    this._albumId,
    this._playbackCoordinator,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final String _albumId;
  final PlaybackCoordinator? _playbackCoordinator;
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
    return _tracks.length - playableTrackCount;
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

    await playbackCoordinator.playTrack(track);
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

  bool _isPlayable(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }
}
