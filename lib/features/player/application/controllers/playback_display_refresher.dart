// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:developer' as developer;

import '../../../../core/events/library_change_signal.dart';
import '../../../library/application/models/library_track.dart';
import 'playback_coordinator.dart';

/// Keeps queued and playing songs showing their current details (SN-50
/// BUG-01).
///
/// Once library edits settle, the queued songs are read again and their
/// display title and credit line are changed in place, so Now Playing, the
/// queue and the media session follow a Track Studio save without
/// restarting playback or touching listening history.
class PlaybackDisplayRefresher {
  PlaybackDisplayRefresher({
    required PlaybackCoordinator coordinator,
    required Future<List<LibraryTrack>> Function() loadTracks,
    LibraryChangeSignal? changes,
    Duration settle = const Duration(milliseconds: 300),
  }) : _coordinator = coordinator,
       _loadTracks = loadTracks {
    _changes = LibraryChangeRefresher(
      signal: changes ?? LibraryChangeSignal.shared,
      kinds: const {
        LibraryChangeKind.libraryEdited,
        LibraryChangeKind.importCompleted,
      },
      onChange: () => unawaited(refresh()),
      settle: settle,
    );
  }

  final PlaybackCoordinator _coordinator;
  final Future<List<LibraryTrack>> Function() _loadTracks;
  late final LibraryChangeRefresher _changes;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed || _coordinator.currentState.queue.isEmpty) {
      return;
    }

    try {
      final tracks = await _loadTracks();

      if (_disposed) {
        return;
      }

      final queuedSongIds = {
        for (final track in _coordinator.currentState.queue.tracks)
          track.songId,
      };

      _coordinator.refreshTrackDisplay(
        tracks.where((track) => queuedSongIds.contains(track.songId)),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Queued song details could not be refreshed (${error.runtimeType})',
        name: 'sonus.playback',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void dispose() {
    _disposed = true;
    _changes.dispose();
  }
}
