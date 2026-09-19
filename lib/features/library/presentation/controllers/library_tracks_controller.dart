import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/track_profile_editing_service.dart';

class LibraryTracksController extends ChangeNotifier {
  factory LibraryTracksController({
    required LibraryQueryRepository repository,
    required PlaybackCoordinator playbackCoordinator,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    TrackProfileEditingService? trackProfileEditingService,
    Random? random,
  }) {
    return LibraryTracksController._(
      repository,
      playbackCoordinator,
      artworkAssignmentService,
      artworkFilePicker,
      trackProfileEditingService,
      random ?? Random(),
    );
  }

  LibraryTracksController._(
    this._repository,
    this._playbackCoordinator,
    this._artworkAssignmentService,
    this._artworkFilePicker,
    this._trackProfileEditingService,
    this._random,
  );

  final LibraryQueryRepository _repository;
  final PlaybackCoordinator _playbackCoordinator;
  final ArtworkAssignmentService? _artworkAssignmentService;
  final ArtworkFilePicker? _artworkFilePicker;
  final TrackProfileEditingService? _trackProfileEditingService;
  final Random _random;

  List<LibraryTrack> _tracks = const [];
  LibraryTrackOrder _order = LibraryTrackOrder.title;

  bool _isLoading = false;
  bool _isShuffleEnabled = false;
  Object? _error;

  List<LibraryTrack> get tracks => _tracks;

  LibraryTrackOrder get order => _order;

  bool get isLoading => _isLoading;

  bool get isShuffleEnabled => _isShuffleEnabled;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isEmpty => !_isLoading && _tracks.isEmpty;

  bool get canEditArtwork {
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

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _tracks = await _repository.getTracks(order: _order);
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

  Future<void> setOrder(LibraryTrackOrder order) async {
    if (_order == order) {
      return;
    }

    _order = order;
    await load();
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    if (_isShuffleEnabled == enabled) {
      return;
    }

    await _playbackCoordinator.setShuffleEnabled(enabled);

    _isShuffleEnabled = enabled;
    notifyListeners();
  }

  Future<void> toggleShuffle() {
    return setShuffleEnabled(!_isShuffleEnabled);
  }

  Future<void> playTrack(LibraryTrack track) {
    return _playbackCoordinator.playTrack(track);
  }

  Future<void> playAll() async {
    if (_tracks.isEmpty) {
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

    await _playbackCoordinator.playTracks(_tracks, startIndex: startIndex);
  }

  Future<void> playNext(LibraryTrack track) {
    return _playbackCoordinator.playNext(track);
  }

  Future<void> addToQueue(LibraryTrack track) {
    return _playbackCoordinator.addToQueue(track);
  }

  Future<bool> changeArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;
    final picker = _artworkFilePicker;

    if (service == null || picker == null) {
      return false;
    }

    final songId = track.songId.trim();

    if (songId.isEmpty) {
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

  Future<bool> clearArtwork(LibraryTrack track) async {
    final service = _artworkAssignmentService;

    if (service == null) {
      return false;
    }

    final songId = track.songId.trim();

    if (songId.isEmpty) {
      return false;
    }

    await service.clearSong(songId);

    await refresh();

    return true;
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
