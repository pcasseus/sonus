import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';

class ArtistProfileController extends ChangeNotifier {
  ArtistProfileController({
    required LibraryQueryRepository repository,
    required String artistId,
    PlaybackCoordinator? playbackCoordinator,
    Random? random,
  }) : this._(repository, artistId, playbackCoordinator, random ?? Random());

  ArtistProfileController._(
    this._repository,
    this._artistId,
    this._playbackCoordinator,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final String _artistId;
  final PlaybackCoordinator? _playbackCoordinator;
  final Random _random;

  LibraryArtist? _artist;
  List<LibraryAlbum> _albums = const [];
  List<LibraryTrack> _tracks = const [];

  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  Object? _error;

  String get artistId => _artistId;

  LibraryArtist? get artist => _artist;
  List<LibraryAlbum> get albums => _albums;
  List<LibraryTrack> get tracks => _tracks;

  bool get isLoading => _isLoading;
  bool get isShuffleEnabled => _isShuffleEnabled;
  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isNotFound {
    return !_isLoading && _error == null && _artist == null;
  }

  bool get hasPlayableTracks {
    return _tracks.any(_isPlayable);
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final artist = await _repository.getArtistById(_artistId);

      if (artist == null) {
        _artist = null;
        _albums = const [];
        _tracks = const [];
        return;
      }

      final albums = await _repository.getAlbumsByArtistId(_artistId);
      final tracks = await _repository.getTracksByArtistId(_artistId);

      _artist = artist;
      _albums = albums;
      _tracks = tracks;
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

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
