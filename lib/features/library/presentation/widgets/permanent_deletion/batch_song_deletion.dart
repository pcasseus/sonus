import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/models/library_track.dart';
import '../../../application/services/permanent_deletion_service.dart';
import '../../../domain/deletion/permanent_deletion_impact.dart';
import 'permanent_deletion_sheet.dart';

/// App Update 1.2 (BUG-03): deleting several selected songs from the
/// library at once, through the unchanged single-song permanent deletion.
///
/// [plan] previews every song and adds them up, read-only, so the listener
/// confirms once, knowing everything that goes. [run] then deletes the
/// songs one at a time, each as its own permanent deletion: one atomic,
/// ledgered and synced operation per song, exactly as when a song is
/// deleted alone. Each song is planned again just before it is deleted,
/// because the songs deleted before it legitimately change its chart
/// details. It stops at the first song that is blocked, gone or changed,
/// and reports how many were deleted; nothing else is touched.
///
/// Music files on the device are never deleted: Sonus only forgets them.
class BatchSongDeletion {
  BatchSongDeletion({required this.preview, required this.delete});

  final Future<PermanentDeletionImpact> Function(PermanentDeletionTarget)
  preview;
  final Future<PermanentDeletionImpact> Function(PermanentDeletionImpact)
  delete;

  Future<BatchSongDeletionPlan> plan(Iterable<String> songIds) async {
    final impacts = <PermanentDeletionImpact>[];
    for (final songId in {...songIds}) {
      impacts.add(await preview(PermanentDeletionTarget.song(songId)));
    }
    return BatchSongDeletionPlan(impacts);
  }

  /// Deletes the planned songs in order. Songs already deleted stay
  /// deleted when a later one stops the batch: each deletion is permanent
  /// on its own, and nothing is rolled back. The outcome names exactly
  /// which songs were deleted and which were kept.
  Future<BatchSongDeletionOutcome> run(BatchSongDeletionPlan plan) async {
    final songIds = [for (final impact in plan.impacts) impact.target.id];
    if (!plan.canProceed) {
      return BatchSongDeletionOutcome(
        deletedSongIds: const [],
        keptSongIds: songIds,
        stopped: BatchSongDeletionStop.blocked,
      );
    }
    final deleted = <String>[];
    BatchSongDeletionOutcome stop(BatchSongDeletionStop reason) =>
        BatchSongDeletionOutcome(
          deletedSongIds: deleted,
          keptSongIds: songIds.skip(deleted.length).toList(),
          stopped: reason,
        );

    for (final confirmed in plan.impacts) {
      final PermanentDeletionImpact current;
      try {
        current = await preview(confirmed.target);
      } catch (_) {
        return stop(BatchSongDeletionStop.failed);
      }
      if (!current.canProceed) return stop(BatchSongDeletionStop.blocked);
      if (!_sameSongs(current, confirmed)) {
        return stop(BatchSongDeletionStop.changed);
      }
      try {
        await delete(current);
      } on StaleDeletionPreview {
        return stop(BatchSongDeletionStop.changed);
      } on DeletionBlocked {
        return stop(BatchSongDeletionStop.blocked);
      } catch (_) {
        // The deletion commits first and then takes the song off the play
        // queue; an error after the commit must not hide a deletion that
        // happened. Whether the song is gone decides how it is counted.
        if (await _isGone(confirmed.target)) {
          deleted.add(confirmed.target.id);
        }
        return stop(BatchSongDeletionStop.failed);
      }
      deleted.add(confirmed.target.id);
    }
    return BatchSongDeletionOutcome(
      deletedSongIds: deleted,
      keptSongIds: const [],
    );
  }

  Future<bool> _isGone(PermanentDeletionTarget target) async {
    try {
      final now = await preview(target);
      return now.blockers.contains(PermanentDeletionBlocker.notFound);
    } catch (_) {
      return false;
    }
  }

  /// The song still is what the listener confirmed (a song deletion
  /// removes only that song).
  static bool _sameSongs(
    PermanentDeletionImpact a,
    PermanentDeletionImpact b,
  ) => a.songIds.length == b.songIds.length && a.songIds.containsAll(b.songIds);
}

/// What deleting the selected songs removes, added up from each song's
/// own preview.
class BatchSongDeletionPlan {
  BatchSongDeletionPlan(List<PermanentDeletionImpact> impacts)
    : impacts = List.unmodifiable(impacts);

  final List<PermanentDeletionImpact> impacts;

  int get songCount => impacts.length;

  Set<PermanentDeletionBlocker> get blockers => {
    for (final impact in impacts) ...impact.blockers,
  };

  bool get canProceed => impacts.isNotEmpty && blockers.isEmpty;

  int get qualifiedStreamCount =>
      impacts.fold(0, (sum, impact) => sum + impact.qualifiedStreamCount);

  int get listenedMs =>
      impacts.fold(0, (sum, impact) => sum + impact.listenedMs);

  int get momentCount =>
      {for (final impact in impacts) ...impact.allMomentIds}.length;

  int get playlistCount => {
    for (final impact in impacts)
      for (final playlist in impact.playlists) playlist.playlistId,
  }.length;

  /// The earliest stored chart week that is recalculated, if any.
  String? get earliestAffectedWeekStartUtc {
    String? earliest;
    for (final impact in impacts) {
      final week = impact.earliestAffectedWeekStartUtc;
      if (week != null && (earliest == null || week.compareTo(earliest) < 0)) {
        earliest = week;
      }
    }
    return earliest;
  }
}

enum BatchSongDeletionStop { blocked, changed, failed }

class BatchSongDeletionOutcome {
  const BatchSongDeletionOutcome({
    required this.deletedSongIds,
    required this.keptSongIds,
    this.stopped,
  });

  /// Permanently deleted, in order. Never undone by a later stop.
  final List<String> deletedSongIds;

  /// Still in the library: the song the batch stopped at and every one
  /// after it.
  final List<String> keptSongIds;

  /// Why the deletion stopped early, or null when every song was deleted.
  final BatchSongDeletionStop? stopped;

  int get deleted => deletedSongIds.length;
  int get kept => keptSongIds.length;
  int get total => deleted + kept;

  bool get isComplete => stopped == null && keptSongIds.isEmpty;
}

/// Asks to delete [tracks] from the library and, once the listener has
/// confirmed, deletes them. Resolves to what happened, or null when the
/// listener cancelled or nothing could be checked.
Future<BatchSongDeletionOutcome?> showBatchSongDeletion(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return null;
  final service = permanentDeletionServiceOf(context);
  final batch = BatchSongDeletion(
    preview: service.preview,
    delete: service.delete,
  );
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await showDialog<BatchSongDeletionOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BatchSongDeletionDialog(
      batch: batch,
      songIds: [for (final track in tracks) track.songId],
    ),
  );
  if (outcome == null) return null;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // A partial result takes longer to read.
        duration: outcome.isComplete
            ? const Duration(seconds: 4)
            : const Duration(seconds: 10),
        content: Text(batchDeletionMessage(outcome)),
      ),
    );
  return outcome;
}

/// The confirmation after a batch deletion. A partial one gives both
/// counts, says the deletions made are permanent (nothing was undone),
/// and that the songs kept stay selected.
String batchDeletionMessage(BatchSongDeletionOutcome outcome) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  if (outcome.isComplete) {
    return 'Deleted ${songs(outcome.deleted)} from your library.';
  }
  final why = switch (outcome.stopped) {
    BatchSongDeletionStop.blocked => 'They cannot be deleted right now.',
    BatchSongDeletionStop.changed => 'They changed after you confirmed.',
    _ => 'Something went wrong while deleting them.',
  };
  final kept = outcome.kept == 1
      ? '1 song was not deleted and is still selected.'
      : '${outcome.kept} songs were not deleted and are still selected.';
  if (outcome.deleted == 0) {
    return 'No songs were deleted. $why';
  }
  return 'Deleted ${outcome.deleted} of ${songs(outcome.total)}. '
      'Those deletions are permanent and were not undone. $kept $why';
}

String _blockerText(PermanentDeletionBlocker blocker) => switch (blocker) {
  PermanentDeletionBlocker.notFound =>
    'Some of these songs are no longer in your library.',
  // Raised only when a whole artist is deleted (never for single songs):
  // the artist's releases hold another artist's songs, or the artist has
  // songs on another artist's release, and those were not confirmed.
  PermanentDeletionBlocker.sharedRecordingsNotConfirmed =>
    'Deleting this artist would also delete songs shared with another '
        'artist. Confirm those songs on the artist\'s profile first.',
  PermanentDeletionBlocker.pendingCloudWrite =>
    'Some changes to these songs have not reached the cloud yet. Sync, '
        'then try again.',
  PermanentDeletionBlocker.cloudDeletionUnavailable =>
    'Your library syncs to a cloud that cannot delete songs permanently '
        'yet, so they would come back.',
};

/// Plans, confirms and runs a batch deletion. Pops with the outcome, or
/// null when cancelled.
class BatchSongDeletionDialog extends StatefulWidget {
  const BatchSongDeletionDialog({
    super.key,
    required this.batch,
    required this.songIds,
  });

  final BatchSongDeletion batch;
  final List<String> songIds;

  @override
  State<BatchSongDeletionDialog> createState() =>
      _BatchSongDeletionDialogState();
}

class _BatchSongDeletionDialogState extends State<BatchSongDeletionDialog> {
  BatchSongDeletionPlan? _plan;
  Object? _error;
  bool _acknowledged = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final plan = await widget.batch.plan(widget.songIds);
      if (mounted) setState(() => _plan = plan);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _delete(BatchSongDeletionPlan plan) async {
    setState(() => _deleting = true);
    final outcome = await widget.batch.run(plan);
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final count = widget.songIds.toSet().length;
    final songs = count == 1 ? '1 song' : '$count songs';

    Widget content;
    var canDelete = false;
    if (_error != null) {
      content = const Text('Could not check what would be deleted.');
    } else if (plan == null) {
      content = const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!plan.canProceed) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nothing was deleted.'),
          const SizedBox(height: 8),
          for (final blocker in plan.blockers)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(_blockerText(blocker)),
            ),
        ],
      );
    } else {
      canDelete = _acknowledged && !_deleting;
      final week = plan.earliestAffectedWeekStartUtc;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deleting these songs is permanent. Their listening history '
            '(every stream and the time listened) is erased, Moments about '
            'them are deleted, they are taken out of every playlist they '
            'are in, and the chart weeks they reached are recalculated '
            'without them. For these songs that means:',
            key: ValueKey<String>('batch-delete-intro'),
          ),
          const SizedBox(height: 8),
          Text(
            '• ${plan.qualifiedStreamCount} '
            '${plan.qualifiedStreamCount == 1 ? 'stream' : 'streams'} and '
            'their listening time',
            key: const ValueKey<String>('batch-delete-streams'),
          ),
          if (plan.momentCount > 0)
            Text(
              '• ${plan.momentCount} '
              '${plan.momentCount == 1 ? 'Moment' : 'Moments'}',
            ),
          if (plan.playlistCount > 0)
            Text(
              '• their places in ${plan.playlistCount} '
              '${plan.playlistCount == 1 ? 'playlist' : 'playlists'}',
            ),
          if (week != null)
            const Text('• chart weeks they reached are recalculated'),
          const SizedBox(height: 8),
          Text(
            'The music files on this device are not deleted.',
            key: const ValueKey<String>('batch-delete-files-kept'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey<String>('batch-delete-acknowledge'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acknowledged,
            onChanged: _deleting
                ? null
                : (value) => setState(() => _acknowledged = value ?? false),
            title: const Text('I understand this cannot be undone.'),
          ),
          if (_deleting) const LinearProgressIndicator(),
        ],
      );
    }

    return AlertDialog(
      key: const ValueKey<String>('batch-delete-dialog'),
      title: Text('Delete $songs from your library?'),
      content: SingleChildScrollView(child: content),
      actions: [
        TextButton(
          key: const ValueKey<String>('batch-delete-cancel'),
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: Text(plan != null && !plan.canProceed ? 'Close' : 'Cancel'),
        ),
        if (plan != null && plan.canProceed)
          FilledButton(
            key: const ValueKey<String>('batch-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: canDelete ? () => unawaited(_delete(plan)) : null,
            child: Text('Delete $songs'),
          ),
      ],
    );
  }
}
