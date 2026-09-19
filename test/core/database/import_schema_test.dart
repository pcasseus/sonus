import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates song import review table with expected columns', () async {
    final db = await appDatabase.database;

    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.songImportReviews})',
    );

    final names = columns.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'song_id',
        'metadata_source',
        'review_reasons',
        'resolved_at',
        'created_at',
        'updated_at',
      }),
    );

    final foreignKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(${DatabaseTables.songImportReviews})',
    );

    expect(
      foreignKeys.any(
        (row) =>
            row['table'] == DatabaseTables.songs && row['from'] == 'song_id',
      ),
      isTrue,
    );
  });
  test(
    'accepts mixed metadata source and rejects unknown metadata source',
    () async {
      final db = await appDatabase.database;

      final now = DateTime.utc(2026, 9, 19).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_mixed_metadata',
        'name': 'Test Artist',
        'canonical_name': 'test artist',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.albums, {
        'id': 'album_mixed_metadata',
        'artist_id': 'artist_mixed_metadata',
        'title': 'Test Album',
        'canonical_title': 'test album',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.albumEditions, {
        'id': 'edition_mixed_metadata',
        'album_id': 'album_mixed_metadata',
        'title': 'Standard',
        'type': 'standard',
        'created_at': now,
        'updated_at': now,
      });

      await db.insert(DatabaseTables.songs, {
        'id': 'song_mixed_metadata',
        'artist_id': 'artist_mixed_metadata',
        'album_id': 'album_mixed_metadata',
        'album_edition_id': 'edition_mixed_metadata',
        'title': 'Mixed Metadata Song',
        'canonical_title': 'mixed metadata song',
        'duration_seconds': 74,
        'track_number': 0,
        'disc_number': 1,
        'is_single': 0,
        'created_at': now,
        'updated_at': now,
      });

      await expectLater(
        db.insert(DatabaseTables.songImportReviews, {
          'song_id': 'song_mixed_metadata',
          'metadata_source': 'mixed',
          'review_reasons': '["missingTrackNumber"]',
          'resolved_at': null,
          'created_at': now,
          'updated_at': now,
        }),
        completes,
      );

      await db.delete(
        DatabaseTables.songImportReviews,
        where: 'song_id = ?',
        whereArgs: ['song_mixed_metadata'],
      );

      await expectLater(
        db.insert(DatabaseTables.songImportReviews, {
          'song_id': 'song_mixed_metadata',
          'metadata_source': 'invalid_source',
          'review_reasons': '[]',
          'resolved_at': null,
          'created_at': now,
          'updated_at': now,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('creates import batch table with expected columns', () async {
    final db = await appDatabase.database;

    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseTables.importBatches})',
    );

    final names = columns.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'id',
        'status',
        'total_count',
        'imported_count',
        'relinked_count',
        'skipped_count',
        'failed_count',
        'created_at',
        'started_at',
        'completed_at',
      }),
    );
  });

  test('accepts a valid pending import batch', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    await expectLater(
      db.insert(DatabaseTables.importBatches, {
        'id': 'batch_valid',
        'status': 'pending',
        'total_count': 3,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
        'started_at': null,
        'completed_at': null,
      }),
      completes,
    );
  });

  test('rejects unknown import batch status', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.importBatches, {
        'id': 'batch_invalid_status',
        'status': 'exploded',
        'total_count': 0,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('rejects negative import batch counts', () async {
    final db = await appDatabase.database;

    final now = DateTime.utc(2026, 9, 10).toIso8601String();

    expect(
      () => db.insert(DatabaseTables.importBatches, {
        'id': 'batch_negative',
        'status': 'pending',
        'total_count': -1,
        'imported_count': 0,
        'relinked_count': 0,
        'skipped_count': 0,
        'failed_count': 0,
        'created_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
