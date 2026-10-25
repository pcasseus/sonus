import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/track_lyrics_repository.dart';
import 'lyrics_state.dart';

class LyricsController extends ChangeNotifier {
  LyricsController({
    required PlaybackCoordinator playbackCoordinator,
    required this._repository,
  }) {
    _subscription = playbackCoordinator.states.listen(_handlePlaybackState);

    _handlePlaybackState(playbackCoordinator.currentState);
  }

  final TrackLyricsRepository _repository;

  late final StreamSubscription<PlaybackState> _subscription;

  LyricsState _state = const LyricsState();
  int _requestGeneration = 0;
  bool _disposed = false;

  LyricsState get state => _state;

  void _handlePlaybackState(PlaybackState playbackState) {
    final songId = playbackState.queue.currentTrack?.songId;

    if (songId == _state.songId) {
      return;
    }

    _requestGeneration++;

    if (songId == null) {
      _setState(const LyricsState());
      return;
    }

    unawaited(_load(songId, _requestGeneration));
  }

  /// Reads the current song's lyrics again: they may have been imported or
  /// changed while it played, or the last read may have failed. Lyrics
  /// already on screen stay visible until the new result arrives.
  Future<void> reload() {
    final songId = _state.songId;

    if (_disposed || songId == null) {
      return Future<void>.value();
    }

    _requestGeneration++;
    final keepShowing = _state.status == LyricsStatus.loaded;

    return _load(songId, _requestGeneration, showLoading: !keepShowing);
  }

  Future<void> _load(
    String songId,
    int generation, {
    bool showLoading = true,
  }) async {
    if (showLoading) {
      _setState(LyricsState(songId: songId, status: LyricsStatus.loading));
    }

    try {
      final lyrics = await _repository.getBySongId(songId);

      if (_disposed || generation != _requestGeneration) {
        return;
      }

      if (lyrics == null || !lyrics.hasLyrics) {
        _setState(LyricsState(songId: songId, status: LyricsStatus.empty));
        return;
      }

      _setState(
        LyricsState(
          songId: songId,
          status: LyricsStatus.loaded,
          lyrics: lyrics,
        ),
      );
    } catch (error) {
      if (_disposed || generation != _requestGeneration) {
        return;
      }

      _setState(
        LyricsState(songId: songId, status: LyricsStatus.failed, error: error),
      );
    }
  }

  void _setState(LyricsState state) {
    if (_disposed) {
      return;
    }

    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
