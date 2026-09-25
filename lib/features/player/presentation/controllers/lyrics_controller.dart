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

  Future<void> _load(String songId, int generation) async {
    _setState(LyricsState(songId: songId, status: LyricsStatus.loading));

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
