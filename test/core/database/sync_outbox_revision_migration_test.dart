import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

void main() {
  sqfliteFfiInit();

  test('v27 pending mutation survives migration to v28', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await db.execute('''
        CREATE TABLE sync_outbox (
          id TEXT PRIMARY KEY NOT NULL,
          user_id TEXT,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      const timestamp = '2026-10-12T12:00:00.000Z';

      await db.insert(DatabaseTables.syncOutbox, {
        'id': 'pending-song-1',
        'user_id': 'user-1',
        'entity_type': 'song',
        'entity_id': 'song-1',
        'operation': 'upsert',
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 27, newVersion: 28);

      final rows = await db.query(DatabaseTables.syncOutbox);

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'pending-song-1');
      expect(rows.single['user_id'], 'user-1');
      expect(rows.single['entity_type'], 'song');
      expect(rows.single['entity_id'], 'song-1');
      expect(rows.single['operation'], 'upsert');
      expect(rows.single['mutation_revision'], 1);
    } finally {
      await db.close();
    }
  });

  test('fresh sync outbox defaults to revision 1', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await SyncSchema.create(db);

      const timestamp = '2026-10-12T12:00:00.000Z';

      await db.insert(DatabaseTables.syncOutbox, {
        'id': 'fresh-song-1',
        'user_id': 'user-1',
        'entity_type': 'song',
        'entity_id': 'song-1',
        'operation': 'upsert',
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      final rows = await db.query(DatabaseTables.syncOutbox);

      expect(rows.single['mutation_revision'], 1);
    } finally {
      await db.close();
    }
  });

  test('sync outbox rejects invalid mutation revision', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    try {
      await SyncSchema.create(db);

      const timestamp = '2026-10-12T12:00:00.000Z';

      await expectLater(
        db.insert(DatabaseTables.syncOutbox, {
          'id': 'invalid-song-1',
          'user_id': 'user-1',
          'entity_type': 'song',
          'entity_id': 'song-1',
          'operation': 'upsert',
          'created_at': timestamp,
          'updated_at': timestamp,
          'mutation_revision': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });
}
