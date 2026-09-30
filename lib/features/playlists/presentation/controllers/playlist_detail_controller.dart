// ignore_for_file: prefer_initializing_formals

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_track.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/playlist_detail.dart';
import '../../application/models/playlist_track.dart';
import '../../application/services/playlist_service.dart';

class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController({
    required PlaylistService service,
    required String playlistId,
    PlaybackCoordinator? playbackCoordinator,
    Random? random,
  }) : _service = service,
       _playlistId = playlistId.trim(),
       _playbackCoordinator = playbackCoordinator,
       _random = random ?? Random();

  final PlaylistService _service;
  final String _playlistId;
  final PlaybackCoordinator? _playbackCoordinator;
  final Random _random;

  PlaylistDetail? _detail;

  bool _isLoading = false;
  bool _isMutating = false;
  bool _isShuffleEnabled = false;
  Object? _error;

  int _requestGeneration = 0;

  String get playlistId => _playlistId;

  PlaylistDetail? get detail => _detail;

  List<PlaylistTrack> get tracks => _detail?.tracks ?? const [];

  bool get isLoading => _isLoading;

  bool get isMutating => _isMutating;

  bool get isBusy => _isLoading || _isMutating;

  bool get isShuffleEnabled => _isShuffleEnabled;

  Object? get error => _error;

  bool get hasError => _error != null;

  bool get isNotFound => !_isLoading && _error == null && _detail == null;

  bool get isEmpty =>
      !_isLoading &&
      _error == null &&
      _detail != null &&
      _detail!.tracks.isEmpty;

  bool get hasPlayableTracks {
    return tracks.any((entry) => isTrackPlayable(entry.track));
  }

  Future<void> load() {
    if (_isLoading) {
      return Future<void>.value();
    }

    return _load();
  }

  Future<void> refresh() => _load();

  Future<bool> rename(String name) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.renamePlaylist(playlistId: _playlistId, name: name);

      await _reloadAfterMutation();

      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> deletePlaylist() async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deletePlaylist(_playlistId);
      _detail = null;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> removeTrack(PlaylistTrack entry) async {
    if (_isMutating) {
      return false;
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      final removed = await _service.removeSong(
        playlistId: _playlistId,
        songId: entry.track.songId,
      );

      if (removed) {
        await _reloadAfterMutation();
      }

      return removed;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> reorder({required int oldIndex, required int newIndex}) async {
    if (_isMutating) {
      return false;
    }

    final current = tracks;

    if (oldIndex < 0 ||
        oldIndex >= current.length ||
        newIndex < 0 ||
        newIndex > current.length) {
      return false;
    }

    var adjustedNewIndex = newIndex;

    if (adjustedNewIndex > oldIndex) {
      adjustedNewIndex--;
    }

    if (adjustedNewIndex == oldIndex) {
      return false;
    }

    final reordered = List<PlaylistTrack>.of(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(adjustedNewIndex, moved);

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.reorderItems(
        playlistId: _playlistId,
        orderedItemIds: [for (final entry in reordered) entry.item.id],
      );

      await _reloadAfterMutation();

      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  bool isTrackVisible(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  bool isTrackPlayable(LibraryTrack track) {
    return !track.isBlocked && isTrackVisible(track);
  }

  Future<bool> reorderVisible({
    required int oldIndex,
    required int newIndex,
  }) async {
    if (_isMutating) {
      return false;
    }

    final current = tracks;
    final visible = [
      for (final entry in current)
        if (isTrackVisible(entry.track)) entry,
    ];

    if (oldIndex < 0 ||
        oldIndex >= visible.length ||
        newIndex < 0 ||
        newIndex > visible.length) {
      return false;
    }

    var adjustedNewIndex = newIndex;

    if (adjustedNewIndex > oldIndex) {
      adjustedNewIndex--;
    }

    if (adjustedNewIndex == oldIndex) {
      return false;
    }

    final reorderedVisible = List<PlaylistTrack>.of(visible);
    final moved = reorderedVisible.removeAt(oldIndex);
    reorderedVisible.insert(adjustedNewIndex, moved);

    var visibleIndex = 0;
    final reorderedFull = <PlaylistTrack>[];

    for (final entry in current) {
      if (isTrackVisible(entry.track)) {
        reorderedFull.add(reorderedVisible[visibleIndex]);
        visibleIndex++;
      } else {
        reorderedFull.add(entry);
      }
    }

    _isMutating = true;
    _error = null;
    notifyListeners();

    try {
      await _service.reorderItems(
        playlistId: _playlistId,
        orderedItemIds: [for (final entry in reorderedFull) entry.item.id],
      );

      await _reloadAfterMutation();

      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<void> playTrack(LibraryTrack track) async {
    final playback = _playbackCoordinator;

    if (playback == null || !isTrackPlayable(track)) {
      return;
    }

    final libraryTracks = [for (final entry in tracks) entry.track];

    final index = libraryTracks.indexWhere(
      (candidate) => candidate.songId == track.songId,
    );

    if (index < 0) {
      await playback.playTrack(track);
      return;
    }

    await playback.playTracks(libraryTracks, startIndex: index);
  }

  Future<void> playAll() async {
    final playback = _playbackCoordinator;

    if (playback == null || tracks.isEmpty) {
      return;
    }

    final libraryTracks = [for (final entry in tracks) entry.track];

    final playableIndexes = <int>[];

    for (var index = 0; index < libraryTracks.length; index++) {
      if (isTrackPlayable(libraryTracks[index])) {
        playableIndexes.add(index);
      }
    }

    if (playableIndexes.isEmpty) {
      return;
    }

    final startIndex = _isShuffleEnabled
        ? playableIndexes[_random.nextInt(playableIndexes.length)]
        : playableIndexes.first;

    await playback.playTracks(libraryTracks, startIndex: startIndex);
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    if (_isShuffleEnabled == enabled) {
      return;
    }

    final playback = _playbackCoordinator;

    if (playback == null) {
      return;
    }

    await playback.setShuffleEnabled(enabled);

    _isShuffleEnabled = enabled;
    notifyListeners();
  }

  Future<void> toggleShuffle() {
    return setShuffleEnabled(!_isShuffleEnabled);
  }

  Future<void> playNext(LibraryTrack track) async {
    final playback = _playbackCoordinator;

    if (playback == null || !isTrackPlayable(track)) {
      return;
    }

    await playback.playNext(track);
  }

  Future<void> addToQueue(LibraryTrack track) async {
    final playback = _playbackCoordinator;

    if (playback == null || !isTrackPlayable(track)) {
      return;
    }

    await playback.addToQueue(track);
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final detail = await _service.getPlaylist(_playlistId);

      if (generation != _requestGeneration) {
        return;
      }

      _detail = detail;
    } on StateError catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      if (error.message.toString().startsWith('Playlist not found:')) {
        _detail = null;
        _error = null;
      } else {
        _error = error;
      }
    } catch (error) {
      if (generation != _requestGeneration) {
        return;
      }

      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadAfterMutation() async {
    _requestGeneration++;

    _detail = await _service.getPlaylist(_playlistId);
  }
}
