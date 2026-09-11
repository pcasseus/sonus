import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';

class PlaybackStateController extends ChangeNotifier {
  PlaybackStateController({required PlaybackCoordinator coordinator})
    : _state = coordinator.currentState {
    _subscription = coordinator.states.listen(_handleStateChanged);
  }

  PlaybackState _state;
  late final StreamSubscription<PlaybackState> _subscription;

  PlaybackState get state => _state;

  void _handleStateChanged(PlaybackState state) {
    if (_state == state) {
      return;
    }

    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
