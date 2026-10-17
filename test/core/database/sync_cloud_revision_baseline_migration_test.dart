import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

void main() {
  sqfliteFfiInit();

  const baselineTable = SyncSchema.cloudRevisionBaselinesTable;

  Future<Database> openTestDatabase() {
    return databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  }

  test('fresh sync schema creates cloud revision baselines', () async {
    final db = await openTestDatabase();

    try {
      await SyncSchema.create(db);

      final tables = await db.rawQuery(
        '''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = ?
        ''',
        [baselineTable],
      );

      expect(tables, hasLength(1));

      final columns = await db.rawQuery('PRAGMA table_info($baselineTable)');

      expect(columns.map((row) => row['name']).toList(), [
        'user_id',
        'entity_type',
        'entity_id',
        'server_revision',
      ]);

      final primaryKey = {
        for (final column in columns) column['name']: column['pk'],
      };

      expect(primaryKey['user_id'], 1);
      expect(primaryKey['entity_type'], 2);
      expect(primaryKey['entity_id'], 3);
      expect(primaryKey['server_revision'], 0);

      expect(await db.query(baselineTable), isEmpty);
    } finally {
      await db.close();
    }
  });

  test('v28 to v29 preserves cursor and pending outbox', () async {
    final db = await openTestDatabase();

    try {
      // Build the relevant version-28 sync tables without
      // creating the new version-29 baseline table.
      await SyncSchema.createSyncState(db);
      await SyncSchema.createSyncOutbox(db);

      const timestamp = '2026-10-16T12:00:00.000Z';

      await db.insert(DatabaseTables.syncState, {
        'user_id': 'user-1',
        'entity_type': 'artist',
        'last_server_updated_at': timestamp,
        'last_server_id': 'artist-1',
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.syncOutbox, {
        'id': 'pending-song-1',
        'user_id': 'user-1',
        'entity_type': 'song',
        'entity_id': 'song-1',
        'operation': 'upsert',
        'created_at': timestamp,
        'updated_at': timestamp,
        'mutation_revision': 5,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 28, newVersion: 29);

      final cursorRows = await db.query(DatabaseTables.syncState);
      final outboxRows = await db.query(DatabaseTables.syncOutbox);
      final baselineRows = await db.query(baselineTable);

      expect(cursorRows, hasLength(1));
      expect(cursorRows.single['last_server_id'], 'artist-1');
      expect(cursorRows.single['last_server_updated_at'], timestamp);

      expect(outboxRows, hasLength(1));
      expect(outboxRows.single['id'], 'pending-song-1');
      expect(outboxRows.single['operation'], 'upsert');
      expect(outboxRows.single['mutation_revision'], 5);

      // A migration cannot invent the cloud revision
      // previously observed by this device.
      expect(baselineRows, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('baseline composite key isolates users and entities', () async {
    final db = await openTestDatabase();

    try {
      await SyncSchema.create(db);

      Future<void> insertBaseline({
        required String userId,
        required String entityType,
        required String entityId,
        required int revision,
      }) async {
        await db.insert(baselineTable, {
          'user_id': userId,
          'entity_type': entityType,
          'entity_id': entityId,
          'server_revision': revision,
        });
      }

      await insertBaseline(
        userId: 'user-1',
        entityType: 'artist',
        entityId: 'shared-id',
        revision: 2,
      );

      await insertBaseline(
        userId: 'user-2',
        entityType: 'artist',
        entityId: 'shared-id',
        revision: 7,
      );

      await insertBaseline(
        userId: 'user-1',
        entityType: 'album',
        entityId: 'shared-id',
        revision: 3,
      );

      expect(await db.query(baselineTable), hasLength(3));

      await expectLater(
        insertBaseline(
          userId: 'user-1',
          entityType: 'artist',
          entityId: 'shared-id',
          revision: 9,
        ),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });

  test('baseline schema rejects invalid values', () async {
    final db = await openTestDatabase();

    try {
      await SyncSchema.create(db);

      Future<void> insertRaw(Map<String, Object?> row) async {
        await db.insert(baselineTable, row);
      }

      const valid = <String, Object?>{
        'user_id': 'user-1',
        'entity_type': 'artist',
        'entity_id': 'artist-1',
        'server_revision': 1,
      };

      for (final invalid in [
        {...valid, 'server_revision': 0},
        {...valid, 'server_revision': -1},
        {...valid, 'entity_type': 'unknown'},
        {...valid, 'user_id': '   '},
        {...valid, 'entity_id': '   '},
      ]) {
        await expectLater(
          insertRaw(invalid),
          throwsA(isA<DatabaseException>()),
        );
      }

      expect(await db.query(baselineTable), isEmpty);
    } finally {
      await db.close();
    }
  });
}
