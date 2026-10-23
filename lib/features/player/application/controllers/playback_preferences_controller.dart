import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../data/services/playback_preferences_store.dart';
import '../../domain/models/playback_preferences.dart';
import '../../domain/models/playback_state.dart';
import 'playback_coordinator.dart';

typedef PlaybackPreferencesLogger = void Function(String message, {int level});

/// Owns device-local playback preferences.
///
/// With "remember shuffle and repeat" on, the listener's last shuffle and
/// repeat modes are recorded as they change and restored at launch. They
/// are only restored while the queue is empty: turning shuffle on reorders
/// the queue, and music the listener already started must never move.
class PlaybackPreferencesController extends ChangeNotifier {
  PlaybackPreferencesController({
    required this._store,
    required this._coordinator,
    PlaybackPreferencesLogger? log,
  }) : _log = log ?? _developerLog {
    _subscription = _coordinator.states.listen(_handleState);
  }

  final PlaybackPreferencesStore _store;
  final PlaybackCoordinator _coordinator;
  final PlaybackPreferencesLogger _log;

  late final StreamSubscription<PlaybackState> _subscription;
  PlaybackPreferences _preferences = const PlaybackPreferences();
  bool _isLoaded = false;
  bool _restoreSkipped = false;
  Object? _saveError;
  Future<void> _pendingSave = Future<void>.value();
  bool _disposed = false;

  PlaybackPreferences get preferences => _preferences;
  bool get isLoaded => _isLoaded;

  /// True when saved modes were not applied because music was already
  /// queued at launch.
  bool get restoreSkipped => _restoreSkipped;

  /// The most recent save failure, until a later save succeeds.
  Object? get saveError => _saveError;

  /// Reads the stored preferences and, if remembering is on, restores the
  /// saved modes. If storage cannot be read, defaults are used and nothing
  /// is overwritten.
  Future<void> load() async {
    try {
      final snapshot = await _store.load();

      if (snapshot.issues.isNotEmpty) {
        _log(
          'Playback preferences partly unreadable; defaults used for: '
          '${snapshot.issues.join(', ')}',
          level: 900,
        );
      }

      _preferences = snapshot.preferences;
    } catch (error, stackTrace) {
      _log(
        'Playback preferences could not be read; using defaults. '
        'error=${error.runtimeType}\n$stackTrace',
        level: 1000,
      );
    }

    if (_disposed) {
      return;
    }

    if (_preferences.rememberShuffleAndRepeat) {
      await _restoreSavedModes();
    }

    if (_disposed) {
      return;
    }

    _isLoaded = true;
    notifyListeners();
  }

  /// Turns remembering on (capturing the current modes) or off (forgetting
  /// the saved modes). The player's current modes never change here.
  Future<void> setRememberShuffleAndRepeat(bool enabled) {
    if (enabled == _preferences.rememberShuffleAndRepeat) {
      return Future<void>.value();
    }

    final current = _coordinator.currentState;
    _preferences = enabled
        ? PlaybackPreferences(
            rememberShuffleAndRepeat: true,
            shuffleEnabled: current.shuffleEnabled,
            repeatMode: current.repeatMode,
          )
        : const PlaybackPreferences();

    notifyListeners();
    return _save();
  }

  Future<void> _restoreSavedModes() async {
    final current = _coordinator.currentState;

    if (current.queue.isNotEmpty) {
      _restoreSkipped = true;
      _log(
        'Saved shuffle and repeat not restored: music was already queued.',
        level: 800,
      );
      return;
    }

    try {
      if (current.shuffleEnabled != _preferences.shuffleEnabled) {
        await _coordinator.setShuffleEnabled(_preferences.shuffleEnabled);
      }
      if (current.repeatMode != _preferences.repeatMode) {
        await _coordinator.setRepeatMode(_preferences.repeatMode);
      }
    } catch (error, stackTrace) {
      _log(
        'Saved shuffle and repeat could not be restored. '
        'error=${error.runtimeType}\n$stackTrace',
        level: 1000,
      );
    }
  }

  void _handleState(PlaybackState state) {
    if (!_isLoaded || _disposed || !_preferences.rememberShuffleAndRepeat) {
      return;
    }

    if (state.shuffleEnabled == _preferences.shuffleEnabled &&
        state.repeatMode == _preferences.repeatMode) {
      return;
    }

    _preferences = _preferences.copyWith(
      shuffleEnabled: state.shuffleEnabled,
      repeatMode: state.repeatMode,
    );
    notifyListeners();
    unawaited(_save());
  }

  /// Saves in order, so the last change always wins.
  Future<void> _save() {
    final snapshot = _preferences;

    final save = _pendingSave.then((_) async {
      try {
        await _store.save(snapshot);

        if (_saveError != null) {
          _saveError = null;
          if (!_disposed) notifyListeners();
        }
      } catch (error, stackTrace) {
        _log(
          'Playback preferences could not be saved; the change applies '
          'until Sonus restarts. error=${error.runtimeType}\n$stackTrace',
          level: 1000,
        );
        _saveError = error;
        if (!_disposed) notifyListeners();
      }
    });

    _pendingSave = save;
    return save;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  static void _developerLog(String message, {int level = 800}) {
    developer.log(message, name: 'sonus.playback', level: level);
  }
}
