// App Update 1.2 patches, Checkpoint 4 (BUG-03): deleting several songs
// from the library at once, through the unchanged single-song permanent
// deletion. Disposable databases and fictional fixtures only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/library/presentation/widgets/permanent_deletion/batch_song_deletion.dart';

const _stamp = '2026-11-01T12:00:00.000Z';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase database;
  late Database db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sonus_batch_delete_');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'batch.db'),
    );
    db = await database.database;
    await db.insert(DatabaseTables.artists, {
      'id': 'nova',
      'name': 'Nova',
      'canonical_name': 'nova',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.albums, {
      'id': 'album',
      'artist_id': 'nova',
      'title': 'First Light',
      'canonical_title': 'first light',
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition',
      'album_id': 'album',
      'title': 'First Light',
      'type': 'standard',
      'is_primary': 1,
      'created_at': _stamp,
      'updated_at': _stamp,
    });
    for (final (index, song) in ['one', 'two', 'three'].indexed) {
      await db.insert(DatabaseTables.songs, {
        'id': song,
        'artist_id': 'nova',
        'album_id': 'album',
        'album_edition_id': 'edition',
        'title': song,
        'canonical_title': song,
        'track_number': index + 1,
        'duration_seconds': 200,
        'created_at': _stamp,
        'updated_at': _stamp,
      });
      for (var play = 0; play < index + 1; play++) {
        final id = '${song}_$play';
        await db.insert(DatabaseTables.playbackSessions, {
          'id': 'session_$id',
          'song_id': song,
          'artist_id': 'nova',
          'album_id': 'album',
          'album_edition_id': 'edition',
          'song_title': song,
          'artist_name': 'Nova',
          'album_title': 'First Light',
          'album_edition_title': 'First Light',
          'started_at': _stamp,
          'ended_at': _stamp,
          'listened_duration_ms': 200000,
          'track_duration_ms': 200000,
          'created_at': _stamp,
          'updated_at': _stamp,
        });
        await db.insert(DatabaseTables.qualifiedPlays, {
          'id': 'play_$id',
          'playback_session_id': 'session_$id',
          'song_id': song,
          'artist_id': 'nova',
          'album_id': 'album',
          'album_edition_id': 'edition',
          'qualified_at': _stamp,
          'listened_duration_ms': 200000,
          'track_duration_ms': 200000,
          'created_at': _stamp,
        });
      }
    }
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  PermanentDeletionService service({bool linkedWithoutCloudSupport = false}) =>
      PermanentDeletionService(
        appDatabase: database,
        isCloudLinked: (_) async => linkedWithoutCloudSupport,
        changes: LibraryChangeSignal(),
      );

  BatchSongDeletion batch(PermanentDeletionService s) =>
      BatchSongDeletion(preview: s.preview, delete: s.delete);

  Future<int> count(String table, [String where = '1']) async =>
      (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
          )).single['n']!
          as int;

  test('the plan adds up every song, and the batch deletes each through the '
      'permanent deletion, keeping the others', () async {
    final b = batch(service());
    final plan = await b.plan(['one', 'three', 'one']);
    expect(plan.songCount, 2, reason: 'each song once');
    expect(plan.canProceed, isTrue);
    expect(plan.qualifiedStreamCount, 1 + 3);

    final outcome = await b.run(plan);
    expect(outcome.isComplete, isTrue);
    expect(outcome.deleted, 2);

    expect(await count(DatabaseTables.songs), 1);
    expect(await count(DatabaseTables.songs, "id = 'two'"), 1);
    expect(await count(DatabaseTables.qualifiedPlays, "song_id = 'two'"), 2);
    expect(await count(DatabaseTables.qualifiedPlays), 2);
    expect(await count(DatabaseTables.playbackSessions), 2);
    // Each song is its own ledgered, journaled deletion, as when deleted
    // alone, so restore and sync keep it gone.
    for (final song in ['one', 'three']) {
      expect(
        await count(
          DatabaseTables.libraryDeletionLedger,
          "entity_type = 'song' AND entity_id = '$song' "
          "AND reason = 'userDeletion'",
        ),
        1,
      );
    }
    expect(await count(DatabaseTables.libraryDeletionJournal), 2);
  });

  test('a blocked song deletes nothing at all (fail closed)', () async {
    final b = batch(service(linkedWithoutCloudSupport: true));
    final plan = await b.plan(['one', 'two']);
    expect(plan.canProceed, isFalse);
    expect(
      plan.blockers,
      contains(PermanentDeletionBlocker.cloudDeletionUnavailable),
    );

    final outcome = await b.run(plan);
    expect(outcome.deleted, 0);
    expect(outcome.stopped, BatchSongDeletionStop.blocked);
    expect(await count(DatabaseTables.songs), 3);
    expect(await count(DatabaseTables.libraryDeletionLedger), 0);
  });

  test('a song that goes meanwhile stops the batch there, with what was '
      'already deleted reported', () async {
    final s = service();
    final b = batch(s);
    final plan = await b.plan(['one', 'two', 'three']);
    // "two" is deleted elsewhere after the listener confirmed.
    await s.delete(await s.preview(const PermanentDeletionTarget.song('two')));

    final outcome = await b.run(plan);
    expect(outcome.deleted, 1);
    expect(outcome.stopped, BatchSongDeletionStop.blocked);
    expect(await count(DatabaseTables.songs, "id = 'three'"), 1);
    expect(outcome.deletedSongIds, ['one']);
    expect(outcome.keptSongIds, ['two', 'three']);
    expect(
      batchDeletionMessage(outcome),
      'Deleted 1 of 3 songs. Those deletions are permanent and were not '
      'undone. 2 songs were not deleted and are still selected. They cannot '
      'be deleted right now.',
    );
  });

  test('an error after a song was deleted (taking it off the queue) still '
      'counts that song as deleted, and stops the batch', () async {
    final s = service();
    final b = BatchSongDeletion(
      preview: s.preview,
      delete: (impact) async {
        await s.delete(impact);
        if (impact.target.id == 'two') throw StateError('queue unavailable');
        return impact;
      },
    );

    final outcome = await b.run(await b.plan(['one', 'two', 'three']));

    expect(outcome.deletedSongIds, ['one', 'two']);
    expect(outcome.keptSongIds, ['three']);
    expect(outcome.stopped, BatchSongDeletionStop.failed);
    expect(await count(DatabaseTables.songs), 1);
    expect(
      batchDeletionMessage(outcome),
      'Deleted 2 of 3 songs. Those deletions are permanent and were not '
      'undone. 1 song was not deleted and is still selected. Something went '
      'wrong while deleting them.',
    );
  });

  test('a failure before any deletion says none were deleted', () {
    expect(
      batchDeletionMessage(
        const BatchSongDeletionOutcome(
          deletedSongIds: [],
          keptSongIds: ['a', 'b'],
          stopped: BatchSongDeletionStop.changed,
        ),
      ),
      'No songs were deleted. They changed after you confirmed.',
    );
    expect(
      batchDeletionMessage(
        const BatchSongDeletionOutcome(
          deletedSongIds: ['a', 'b'],
          keptSongIds: [],
        ),
      ),
      'Deleted 2 songs from your library.',
    );
  });

  testWidgets('the dialog says files are kept and deletes only once the '
      'listener acknowledges it', (tester) async {
    final b = batch(service());
    BatchSongDeletionOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  outcome = await showDialog<BatchSongDeletionOutcome>(
                    context: context,
                    builder: (_) => BatchSongDeletionDialog(
                      batch: b,
                      songIds: const ['one', 'two'],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    final confirm = find.byKey(const ValueKey<String>('batch-delete-confirm'));
    for (var i = 0; i < 40 && confirm.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(find.text('Delete 2 songs from your library?'), findsOneWidget);
    final intro = tester
        .widget<Text>(find.byKey(const ValueKey<String>('batch-delete-intro')))
        .data!;
    for (final consequence in [
      'permanent',
      'listening history',
      'Moments',
      'playlist',
      'chart weeks',
      'recalculated',
    ]) {
      expect(intro, contains(consequence));
    }
    expect(
      find.byKey(const ValueKey<String>('batch-delete-files-kept')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('batch-delete-acknowledge')),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    for (var i = 0; i < 60 && outcome == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(outcome?.deleted, 2);
    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 1);
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    final b = batch(service());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchSongDeletionDialog(batch: b, songIds: const ['one']),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(await tester.runAsync(() => count(DatabaseTables.songs)), 3);
  });

  group('Android Back while deleting (App Update 1.2 release review)', () {
    final dialog = find.byKey(const ValueKey<String>('batch-delete-dialog'));
    final confirm = find.byKey(const ValueKey<String>('batch-delete-confirm'));

    /// Lets the real database work run until [done] (or a bound).
    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 80 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    /// Opens the batch dialog the way the Tracks page does, through
    /// [showBatchSongDeletionDialog], so its confirmation is shown too.
    Future<
      ({bool Function() closed, BatchSongDeletionOutcome? Function() outcome})
    >
    open(WidgetTester tester, BatchSongDeletion b, List<String> ids) async {
      var closed = false;
      BatchSongDeletionOutcome? outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    outcome = await showBatchSongDeletionDialog(
                      context,
                      b,
                      ids,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester, () => confirm.evaluate().isNotEmpty);
      return (closed: () => closed, outcome: () => outcome);
    }

    Future<void> acknowledgeAndDelete(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('batch-delete-acknowledge')),
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
    }

    /// Back, as Android sends it, while the first song is still being
    /// deleted: the dialog stays open.
    Future<void> backWhileDeleting(
      WidgetTester tester,
      Completer<void> firstSong,
    ) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(dialog, findsOneWidget, reason: 'Back is held while deleting');
      firstSong.complete();
    }

    testWidgets('before deletion begins, Back still cancels and deletes '
        'nothing', (tester) async {
      final opened = await open(tester, batch(service()), const ['one', 'two']);

      await tester.binding.handlePopRoute();
      await settle(tester, opened.closed);

      expect(opened.closed(), isTrue);
      expect(opened.outcome(), isNull);
      expect(dialog, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(await tester.runAsync(() => count(DatabaseTables.songs)), 3);
    });

    testWidgets('success: Back during deletion waits, then the full result '
        'is shown', (tester) async {
      final s = service();
      final firstSong = Completer<void>();
      final b = BatchSongDeletion(
        preview: s.preview,
        delete: (impact) async {
          if (impact.target.id == 'one') await firstSong.future;
          return s.delete(impact);
        },
      );
      final opened = await open(tester, b, const ['one', 'two']);

      await acknowledgeAndDelete(tester);
      await backWhileDeleting(tester, firstSong);
      await settle(tester, opened.closed);

      expect(opened.outcome()?.isComplete, isTrue);
      expect(opened.outcome()?.deletedSongIds, ['one', 'two']);
      expect(find.text('Deleted 2 songs from your library.'), findsOneWidget);
      expect(await tester.runAsync(() => count(DatabaseTables.songs)), 1);
    });

    testWidgets('failure: Back during deletion waits, then says nothing was '
        'deleted', (tester) async {
      final s = service();
      final firstSong = Completer<void>();
      final reports = <(BatchDeletionStep, Type, BatchDeletionPosition?)>[];
      final b = BatchSongDeletion(
        preview: s.preview,
        delete: (impact) async {
          await firstSong.future;
          throw StateError('database unavailable');
        },
        reportFailure: (step, error, _, {position}) =>
            reports.add((step, error.runtimeType, position)),
      );
      final opened = await open(tester, b, const ['one', 'two']);

      await acknowledgeAndDelete(tester);
      await backWhileDeleting(tester, firstSong);
      await settle(tester, opened.closed);

      expect(opened.outcome()?.deleted, 0);
      expect(opened.outcome()?.stopped, BatchSongDeletionStop.failed);
      expect(
        find.text(
          'No songs were deleted. Something went wrong while deleting them.',
        ),
        findsOneWidget,
      );
      expect(reports, [
        (BatchDeletionStep.delete, StateError, (index: 0, of: 2)),
      ]);
      expect(await tester.runAsync(() => count(DatabaseTables.songs)), 3);
    });

    testWidgets('partial completion: Back during deletion waits, then names '
        'what was deleted and what was kept', (tester) async {
      final s = service();
      final firstSong = Completer<void>();
      final b = BatchSongDeletion(
        preview: s.preview,
        delete: (impact) async {
          if (impact.target.id == 'one') await firstSong.future;
          if (impact.target.id == 'three') throw StateError('unavailable');
          return s.delete(impact);
        },
        reportFailure: (_, _, _, {position}) {},
      );
      final opened = await open(tester, b, const ['one', 'two', 'three']);

      await acknowledgeAndDelete(tester);
      await backWhileDeleting(tester, firstSong);
      await settle(tester, opened.closed);

      expect(opened.outcome()?.deletedSongIds, ['one', 'two']);
      expect(opened.outcome()?.keptSongIds, ['three']);
      expect(
        find.text(
          'Deleted 2 of 3 songs. Those deletions are permanent and were not '
          'undone. 1 song was not deleted and is still selected. Something '
          'went wrong while deleting them.',
        ),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => count(DatabaseTables.songs)), 1);
    });
  });

  group('diagnostics', () {
    test('a failure is recorded with its step, place and type only, never '
        'its message', () {
      final summary = batchDeletionFailureSummary(
        BatchDeletionStep.delete,
        StateError(
          'Nova – First Light – one: /storage/emulated/0/Music/one.mp3',
        ),
        position: (index: 1, of: 3),
      );
      expect(
        summary,
        'Batch song deletion failed at delete (song 2 of 3): StateError',
      );
      for (final secret in ['Nova', 'First Light', 'storage', '.mp3']) {
        expect(summary, isNot(contains(secret)));
      }
    });

    test(
      'every failing step is reported, and the outcome is unchanged',
      () async {
        final s = service();
        final reports = <(BatchDeletionStep, BatchDeletionPosition?)>[];
        void report(
          BatchDeletionStep step,
          Object error,
          StackTrace stackTrace, {
          BatchDeletionPosition? position,
        }) => reports.add((step, position));

        // The re-check before deleting fails.
        var previews = 0;
        final recheck = BatchSongDeletion(
          preview: (target) {
            if (++previews > 2) throw StateError('closed');
            return s.preview(target);
          },
          delete: s.delete,
          reportFailure: report,
        );
        final stopped = await recheck.run(await recheck.plan(['one', 'two']));
        expect(stopped.deleted, 0);
        expect(stopped.stopped, BatchSongDeletionStop.failed);

        // The deletion fails, and so does the check whether it happened.
        var failing = false;
        final gone = BatchSongDeletion(
          preview: (target) {
            if (failing) throw StateError('closed');
            return s.preview(target);
          },
          delete: (impact) {
            failing = true;
            throw StateError('closed');
          },
          reportFailure: report,
        );
        final kept = await gone.run(await gone.plan(['three']));
        expect(kept.keptSongIds, ['three']);
        expect(kept.stopped, BatchSongDeletionStop.failed);

        expect(reports, [
          (BatchDeletionStep.recheck, (index: 0, of: 2)),
          (BatchDeletionStep.delete, (index: 0, of: 1)),
          (BatchDeletionStep.confirmGone, (index: 0, of: 1)),
        ]);
        expect(await count(DatabaseTables.songs), 3);
      },
    );

    testWidgets('a plan that cannot be checked is reported and still says so', (
      tester,
    ) async {
      final reports = <BatchDeletionStep>[];
      final b = BatchSongDeletion(
        preview: (_) async => throw StateError('closed'),
        delete: (impact) async => impact,
        reportFailure: (step, _, _, {position}) => reports.add(step),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchSongDeletionDialog(batch: b, songIds: const ['one']),
          ),
        ),
      );
      for (var i = 0; i < 20 && reports.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump();
      expect(reports, [BatchDeletionStep.plan]);
      expect(
        find.text('Could not check what would be deleted.'),
        findsOneWidget,
      );
    });
  });
}
