// App Update 1.2 patches, Checkpoint 4 (BUG-03): deleting several songs
// from the library at once, through the unchanged single-song permanent
// deletion. Disposable databases and fictional fixtures only.
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
}
