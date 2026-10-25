import 'dart:async';
import 'dart:developer' as developer;

import '../../../library/application/models/library_track.dart';
import '../../data/services/playback_session_store.dart';
import '../../domain/models/playback_session_snapshot.dart';
import '../../domain/models/playback_state.dart';
import 'playback_coordinator.dart';

typedef RestorationLogger = void Function(String message, {int level});

enum PlaybackRestoreOutcome {
  /// The saved queue is back, paused.
  restored,

  /// Nothing was saved.
  nothingSaved,

  /// Every saved song is now missing, unavailable or blacklisted.
  nothingPlayable,

  /// Music was already queued, so nothing was replaced.
  skippedBusy,

  /// Restoring failed; Sonus starts with an empty queue.
  failed,
}

/// Brings the last queue back after Sonus restarts, **paused**.
///
/// It goes through the [PlaybackCoordinator] like any other caller and
/// never presses play, so restoring cannot start a listening session or
/// record a stream: analytics only reacts to playback actually starting.
///
/// Recording starts only after the restore attempt, so the empty queue
/// Sonus starts with can never overwrite the saved session.
class PlaybackRestorationController {
  PlaybackRestorationController({
    required this._store,
    required this._coordinator,
    RestorationLogger? log,
  }) : _log = log ?? _developerLog;

  /// While playing, the saved position is refreshed this often.
  static const Duration positionSaveInterval = Duration(seconds: 10);

  final PlaybackSessionStore _store;
  final PlaybackCoordinator _coordinator;
  final RestorationLogger _log;

  StreamSubscription<PlaybackState>? _subscription;
  Future<void> _pendingSave = Future<void>.value();
  PlaybackSessionSnapshot? _lastSaved;
  bool _cleared = false;
  bool _attempted = false;
  bool _disposed = false;

  /// Restores the saved session once, using [loadTracks] to re-read the
  /// library. Later calls return [PlaybackRestoreOutcome.skippedBusy].
  Future<PlaybackRestoreOutcome> restore(
    Future<List<LibraryTrack>> Function() loadTracks,
  ) async {
    if (_attempted) return PlaybackRestoreOutcome.skippedBusy;
    _attempted = true;

    try {
      return await _restore(loadTracks);
    } catch (error, stackTrace) {
      _log(
        'Playback session could not be restored. '
        'error=${error.runtimeType}\n$stackTrace',
        level: 1000,
      );
      return PlaybackRestoreOutcome.failed;
    } finally {
      _startRecording();
    }
  }

  Future<PlaybackRestoreOutcome> _restore(
    Future<List<LibraryTrack>> Function() loadTracks,
  ) async {
    if (_coordinator.currentState.queue.isNotEmpty) {
      return PlaybackRestoreOutcome.skippedBusy;
    }

    final snapshot = await _store.load();
    if (snapshot == null) return PlaybackRestoreOutcome.nothingSaved;

    final byId = {for (final track in await loadTracks()) track.songId: track};

    // Keep the saved order, dropping songs that are gone or not playable.
    final tracks = <LibraryTrack>[];
    final restoredIndexOf = <int, int>{};
    for (var i = 0; i < snapshot.songIds.length; i++) {
      final track = byId[snapshot.songIds[i]];
      if (track != null && PlaybackCoordinator.isPlayable(track)) {
        restoredIndexOf[i] = tracks.length;
        tracks.add(track);
      }
    }

    if (tracks.isEmpty) {
      await _clear();
      return PlaybackRestoreOutcome.nothingPlayable;
    }

    // Resume the same song where it was; if it is gone, start the next
    // playable one from the beginning.
    var startIndex = 0;
    var position = Duration.zero;
    final sameSong = restoredIndexOf[snapshot.currentIndex];
    if (sameSong != null) {
      startIndex = sameSong;
      position = snapshot.position;
    } else {
      for (var i = snapshot.currentIndex; i < snapshot.songIds.length; i++) {
        final next = restoredIndexOf[i];
        if (next != null) {
          startIndex = next;
          break;
        }
      }
    }

    // The listener may have started something while the library loaded.
    if (_disposed || _coordinator.currentState.queue.isNotEmpty) {
      return PlaybackRestoreOutcome.skippedBusy;
    }

    await _coordinator.playTracks(
      tracks,
      startIndex: startIndex,
      autoPlay: false,
    );
    if (position > Duration.zero) {
      await _coordinator.seek(position);
    }

    return PlaybackRestoreOutcome.restored;
  }

  /// Saves the current position now, e.g. when Sonus goes to the
  /// background, where the process may be killed without warning.
  Future<void> saveNow() {
    if (!_attempted || _disposed) return Future<void>.value();
    return _record(_coordinator.currentState, force: true);
  }

  void _startRecording() {
    if (_disposed || _subscription != null) return;
    _subscription = _coordinator.states.listen(
      (state) => unawaited(_record(state)),
    );
  }

  Future<void> _record(PlaybackState state, {bool force = false}) {
    final queue = state.queue;

    // An emptied queue or a finished one has nothing worth resuming.
    if (queue.isEmpty ||
        !queue.hasCurrentTrack ||
        state.status == PlaybackStatus.completed) {
      return _clear();
    }

    final snapshot = PlaybackSessionSnapshot(
      songIds: [for (final track in queue.tracks) track.songId],
      currentIndex: queue.currentIndex,
      position: state.position,
    );
    final last = _lastSaved;

    final changed =
        force ||
        last == null ||
        last.currentIndex != snapshot.currentIndex ||
        !_sameSongs(last.songIds, snapshot.songIds) ||
        state.status != PlaybackStatus.playing ||
        (snapshot.position - last.position).abs() >= positionSaveInterval;

    if (!changed || last == snapshot) return _pendingSave;

    _lastSaved = snapshot;
    _cleared = false;
    return _chain(() => _store.save(snapshot), 'saved');
  }

  Future<void> _clear() {
    if (_cleared) return _pendingSave;
    _cleared = true;
    _lastSaved = null;
    return _chain(_store.clear, 'cleared');
  }

  /// Writes in order, so the last state always wins.
  Future<void> _chain(Future<void> Function() write, String what) {
    final next = _pendingSave.then((_) async {
      try {
        await write();
      } catch (error, stackTrace) {
        _log(
          'Playback session could not be $what. '
          'error=${error.runtimeType}\n$stackTrace',
          level: 900,
        );
      }
    });
    _pendingSave = next;
    return next;
  }

  static bool _sameSongs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
  }

  static void _developerLog(String message, {int level = 800}) {
    developer.log(message, name: 'sonus.playback', level: level);
  }
}
