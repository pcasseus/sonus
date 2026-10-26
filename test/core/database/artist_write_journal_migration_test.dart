import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

void main() {
  sqfliteFfiInit();

  const journal = SyncSchema.artistWriteJournalTable;
  final createdAt = DateTime.utc(2026, 10, 18).toIso8601String();

  Map<String, Object?> journalRow({
    String userId = 'user_1',
    String artistId = 'artist_1',
    String outboxId = 'outbox_1',
    int mutationRevision = 1,
    String operation = 'update',
    int? expectedRevision = 7,
    String requestJson = r'{"p_artist_id":"artist_1"}',
  }) {
    return {
      'user_id': userId,
      'artist_id': artistId,
      'outbox_id': outboxId,
      'mutation_revision': mutationRevision,
      'operation': operation,
      'expected_server_revision': expectedRevision,
      'request_json': requestJson,
      'created_at': createdAt,
    };
  }

  test('fresh version 31 database creates artist recovery journal', () async {
    final directory = await Directory.systemTemp.createTemp('sonus_journal_');
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/sonus.db',
    );

    try {
      final db = await app.database;
      final version = await db.rawQuery('PRAGMA user_version');

      expect(version.single['user_version'], 40);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [journal],
      );

      expect(tables, hasLength(1));

      final columns = await db.rawQuery('PRAGMA table_info($journal)');
      expect(
        columns.map((column) => column['name']),
        containsAll([
          'user_id',
          'artist_id',
          'outbox_id',
          'mutation_revision',
          'operation',
          'expected_server_revision',
          'request_json',
          'created_at',
        ]),
      );
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  });

  test('version 29 upgrade retains outbox and revision baseline', () async {
    final directory = await Directory.systemTemp.createTemp('sonus_upgrade_');
    final databasePath = '${directory.path}/sonus.db';

    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 29,
        onCreate: (db, version) async {
          await SyncSchema.createSyncOutbox(db);
          await SyncSchema.createCloudRevisionBaselines(db);
        },
      ),
    );

    try {
      await oldDatabase.insert(DatabaseTables.syncOutbox, {
        'id': 'outbox_existing',
        'user_id': 'user_1',
        'entity_type': 'artist',
        'entity_id': 'artist_1',
        'operation': 'upsert',
        'created_at': createdAt,
        'updated_at': createdAt,
        'mutation_revision': 4,
      });

      await oldDatabase.insert(SyncSchema.cloudRevisionBaselinesTable, {
        'user_id': 'user_1',
        'entity_type': 'artist',
        'entity_id': 'artist_1',
        'server_revision': 7,
      });
    } finally {
      await oldDatabase.close();
    }

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    try {
      final db = await upgraded.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        40,
      );

      final pending = await db.query(DatabaseTables.syncOutbox);
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'outbox_existing');
      expect(pending.single['mutation_revision'], 4);

      final baselines = await db.query(SyncSchema.cloudRevisionBaselinesTable);
      expect(baselines, hasLength(1));
      expect(baselines.single['server_revision'], 7);

      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [journal],
        ),
        hasLength(1),
      );
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });

  test('journal rejects duplicate unresolved and malformed records', () async {
    final directory = await Directory.systemTemp.createTemp('sonus_checks_');
    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/sonus.db',
    );

    try {
      final db = await app.database;

      await db.insert(journal, journalRow());

      Future<void> rejected(Map<String, Object?> row) async {
        await expectLater(
          db.insert(journal, row),
          throwsA(isA<DatabaseException>()),
        );
      }

      await rejected(journalRow(outboxId: 'outbox_2', mutationRevision: 2));

      await rejected(journalRow(artistId: 'artist_2'));

      await rejected(
        journalRow(
          artistId: 'artist_2',
          outboxId: 'outbox_2',
          mutationRevision: 0,
        ),
      );

      await rejected(
        journalRow(
          artistId: 'artist_2',
          outboxId: 'outbox_2',
          operation: 'invalid',
        ),
      );

      await rejected(
        journalRow(
          artistId: 'artist_2',
          outboxId: 'outbox_2',
          operation: 'create',
          expectedRevision: 1,
        ),
      );

      await rejected(
        journalRow(
          artistId: 'artist_2',
          outboxId: 'outbox_2',
          operation: 'delete',
          expectedRevision: null,
        ),
      );

      await rejected(
        journalRow(artistId: 'artist_2', outboxId: 'outbox_2', userId: ' '),
      );

      await rejected(
        journalRow(
          artistId: 'artist_2',
          outboxId: 'outbox_2',
          requestJson: ' ',
        ),
      );

      expect(await db.query(journal), hasLength(1));
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  });

  test('journal request snapshot survives database restart', () async {
    final directory = await Directory.systemTemp.createTemp('sonus_restart_');
    final databasePath = '${directory.path}/sonus.db';
    final request = r'{"p_artist_id":"artist_1","p_expected_revision":7}';

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    try {
      await (await first.database).insert(
        journal,
        journalRow(requestJson: request),
      );
    } finally {
      await first.close();
    }

    final reopened = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
    );

    try {
      final records = await (await reopened.database).query(journal);

      expect(records, hasLength(1));
      expect(records.single['request_json'], request);
      expect(records.single['outbox_id'], 'outbox_1');
      expect(records.single['mutation_revision'], 1);
      expect(records.single['expected_server_revision'], 7);
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });
}
