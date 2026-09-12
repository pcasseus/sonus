import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
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
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    Random? random,
  }) : this._(
         repository,
         artistId,
         playbackCoordinator,
         artworkAssignmentService,
         artworkFilePicker,
         random ?? Random(),
       );

  ArtistProfileController._(
    this._repository,
    this._artistId,
    this._playbackCoordinator,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final String _artistId;
  final PlaybackCoordinator? _playbackCoordinator;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
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
    return _tracks.any(_isPlayable);
  }

  bool get canEditArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
  }

  bool get canEditTrackArtwork {
    return _artworkAssignmentService != null && _artworkFilePicker != null;
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

  Future<bool> changeHeaderArtwork() async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (service == null || picker == null) {
      return false;
    }

    final filePath = await picker.pickArtworkFile();

    if (filePath == null) {
      return false;
    }

    await service.assignArtistHeader(artistId: _artistId, filePath: filePath);

    await refresh();

    return true;
  }

  Future<bool> clearHeaderArtwork() async {
    final service = _artworkAssignmentService;

    if (service == null) {
      return false;
    }

    await service.clearArtistHeader(_artistId);

    await refresh();

    return true;
  }

  Future<bool> changeTopArtistsArtwork() async {
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
    );

    await refresh();

    return true;
  }

  Future<bool> clearTopArtistsArtwork() async {
    final service = _artworkAssignmentService;

    if (service == null) {
      return false;
    }

    await service.clearArtistTopArtists(_artistId);

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
