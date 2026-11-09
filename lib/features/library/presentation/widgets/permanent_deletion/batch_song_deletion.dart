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

  Future<BatchSongDeletionOutcome> run(BatchSongDeletionPlan plan) async {
    if (!plan.canProceed) {
      return BatchSongDeletionOutcome(
        deleted: 0,
        total: plan.songCount,
        stopped: BatchSongDeletionStop.blocked,
      );
    }
    var deleted = 0;
    for (final confirmed in plan.impacts) {
      final PermanentDeletionImpact current;
      try {
        current = await preview(confirmed.target);
      } catch (_) {
        return _stopped(deleted, plan, BatchSongDeletionStop.failed);
      }
      if (!current.canProceed) {
        return _stopped(deleted, plan, BatchSongDeletionStop.blocked);
      }
      if (!_sameSongs(current, confirmed)) {
        return _stopped(deleted, plan, BatchSongDeletionStop.changed);
      }
      try {
        await delete(current);
      } on StaleDeletionPreview {
        return _stopped(deleted, plan, BatchSongDeletionStop.changed);
      } on DeletionBlocked {
        return _stopped(deleted, plan, BatchSongDeletionStop.blocked);
      } catch (_) {
        return _stopped(deleted, plan, BatchSongDeletionStop.failed);
      }
      deleted++;
    }
    return BatchSongDeletionOutcome(deleted: deleted, total: plan.songCount);
  }

  static BatchSongDeletionOutcome _stopped(
    int deleted,
    BatchSongDeletionPlan plan,
    BatchSongDeletionStop reason,
  ) => BatchSongDeletionOutcome(
    deleted: deleted,
    total: plan.songCount,
    stopped: reason,
  );

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
    required this.deleted,
    required this.total,
    this.stopped,
  });

  final int deleted;
  final int total;

  /// Why the deletion stopped early, or null when every song was deleted.
  final BatchSongDeletionStop? stopped;

  bool get isComplete => stopped == null && deleted == total;
}

/// Asks to delete [tracks] from the library and, once the listener has
/// confirmed, deletes them. Resolves to how many songs were deleted.
Future<int> showBatchSongDeletion(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return 0;
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
  if (outcome == null) return 0;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(batchDeletionMessage(outcome))));
  return outcome.deleted;
}

/// The confirmation after a batch deletion.
String batchDeletionMessage(BatchSongDeletionOutcome outcome) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  if (outcome.isComplete) {
    return 'Deleted ${songs(outcome.deleted)} from your library.';
  }
  final why = switch (outcome.stopped) {
    BatchSongDeletionStop.blocked => 'The rest cannot be deleted right now.',
    BatchSongDeletionStop.changed =>
      'The rest changed meanwhile and were kept.',
    _ => 'The rest could not be deleted.',
  };
  return 'Deleted ${songs(outcome.deleted)} of ${outcome.total}. $why';
}

String _blockerText(PermanentDeletionBlocker blocker) => switch (blocker) {
  PermanentDeletionBlocker.notFound =>
    'Some of these songs are no longer in your library.',
  PermanentDeletionBlocker.sharedRecordingsNotConfirmed =>
    'Some of these songs are shared with another artist.',
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
          Text(
            'These songs leave your library for good, with everything '
            'recorded about them:',
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
