// App Update 1.3 new-release debuts (user rules 2026-11-16): the proof is
// read from stored data only: the chart history origin (moved by a
// restore), the deletion journal's Moments cutoff, and each song's first
// qualified play.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/chart_schema.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_repository.dart';
import 'package:sonus_next/features/charts/data/services/sqlite_new_release_evidence_reader.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_deletion_journal_reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase database;
  late SqliteNewReleaseEvidenceReader reader;

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    reader = SqliteNewReleaseEvidenceReader(
      database,
      historyOriginUtc: SqliteChartRepository(database).chartHistoryOriginUtc,
      momentsCutoffUtc: SqliteDeletionJournalReader(
        () async => database.database,
      ).momentsCutoff,
    );
  });
  tearDown(() => database.close());

  var sequence = 0;
  Future<void> play(String songId, DateTime at) async {
    final db = await database.database;
    final id = 'p${sequence++}';
    final stamp = at.toUtc().toIso8601String();
    await db.insert(DatabaseTables.playbackSessions, {
      'id': 's$id',
      'song_id': songId,
      'artist_id': 'artist-1',
      'album_id': 'album-1',
      'album_edition_id': 'edition-1',
      'song_title': songId,
      'artist_name': 'Artist',
      'album_title': 'Album',
      'album_edition_title': 'Album',
      'started_at': stamp,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': id,
      'playback_session_id': 's$id',
      'song_id': songId,
      'artist_id': 'artist-1',
      'album_id': 'album-1',
      'album_edition_id': 'edition-1',
      'qualified_at': stamp,
      'listened_duration_ms': 60000,
      'track_duration_ms': 180000,
      'created_at': stamp,
    });
  }

  test('each song\'s earliest stored play; songs without plays are left '
      'out', () async {
    await play('song-a', DateTime.utc(2026, 11, 20, 9));
    await play('song-a', DateTime.utc(2026, 11, 17, 8, 30));
    await play('song-a', DateTime.utc(2026, 11, 18));
    await play('song-b', DateTime.utc(2026, 11, 16));
    await play('song-other', DateTime.utc(2026, 1, 1));

    final first = await reader.firstPlays({'song-a', 'song-b', 'song-none'});
    expect(first, {
      'song-a': DateTime.utc(2026, 11, 17, 8, 30),
      'song-b': DateTime.utc(2026, 11, 16),
    });
    expect(await reader.firstPlays(const {}), isEmpty);
  });

  test('many songs are read in parameterized chunks', () async {
    for (var i = 0; i < 450; i += 50) {
      await play('song-$i', DateTime.utc(2026, 11, 16, 0, i ~/ 50));
    }
    final ids = {for (var i = 0; i < 900; i++) 'song-$i'};
    final first = await reader.firstPlays(ids);
    expect(first, hasLength(9));
    expect(first['song-400'], DateTime.utc(2026, 11, 16, 0, 8));
  });

  test('the chart history origin, moved by a restore', () async {
    final db = await database.database;
    final created = (await reader.read(const {})).historyOriginUtc;
    expect(created, isNotNull);

    final restoredAt = DateTime.utc(2026, 11, 25, 10);
    await ChartSchema.resetChartHistoryOrigin(db, restoredAt);
    expect((await reader.read(const {})).historyOriginUtc, restoredAt);
  });

  test('the latest permanent deletion is the Moments cutoff', () async {
    expect((await reader.read(const {})).momentsCutoffUtc, isNull);
    final db = await database.database;
    final deletedAt = DateTime.utc(2026, 11, 21, 7);
    await db.insert(DatabaseTables.libraryDeletionJournal, {
      'id': 'deletion-1',
      'operation': 'userDeletion',
      'target_type': 'song',
      'target_id': 'song-x',
      'committed_at': deletedAt.toIso8601String(),
    });
    final evidence = await reader.read({'song-a'});
    expect(evidence.momentsCutoffUtc, deletedAt);
    expect(
      evidence.coverageFrom(NewReleaseDebutStart(DateTime.utc(2026, 11, 15))),
      deletedAt,
    );
  });
}
