import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';

/// App Update 1.2 (BUG-06): a page's Shuffle control shows and changes the
/// player's own shuffle mode, never a copy taken when the page opened.
///
/// Album, Artist, Tracks and Playlist pages each kept their own flag, read
/// once (Playlists always started at "off"). After shuffle was changed
/// anywhere else (Now Playing, the notification, another page) the page's
/// toggle and its Play/Shuffle buttons acted on the wrong mode: a tap did
/// nothing, or turned on a shuffle that was already on, dealing the songs
/// already played back into the cycle.
///
/// Call [watchPlaybackShuffle] once, from the constructor.
mixin PlaybackShuffleMode on ChangeNotifier {
  /// The player whose mode the page shows; null when the page has none.
  PlaybackCoordinator? get shufflePlayback;

  StreamSubscription<PlaybackState>? _shuffleWatch;
  bool? _shownShuffle;
  bool _shuffleDisposed = false;

  /// Follows the player's mode, notifying when it changes elsewhere.
  void watchPlaybackShuffle() {
    final playback = shufflePlayback;
    if (playback == null || _shuffleWatch != null) return;
    _shownShuffle = playback.currentState.shuffleEnabled;
    _shuffleWatch = playback.states.listen((state) {
      if (_shuffleDisposed || state.shuffleEnabled == _shownShuffle) return;
      _shownShuffle = state.shuffleEnabled;
      notifyListeners();
    });
  }

  bool get isShuffleEnabled =>
      shufflePlayback?.currentState.shuffleEnabled ?? false;

  Future<void> setShuffleEnabled(bool enabled) async {
    final playback = shufflePlayback;
    if (playback == null || playback.currentState.shuffleEnabled == enabled) {
      return;
    }

    await playback.setShuffleEnabled(enabled);

    if (_shuffleDisposed) return;
    _shownShuffle = enabled;
    notifyListeners();
  }

  Future<void> toggleShuffle() => setShuffleEnabled(!isShuffleEnabled);

  @override
  void dispose() {
    _shuffleDisposed = true;
    unawaited(_shuffleWatch?.cancel());
    super.dispose();
  }
}
