import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

void main() {
  sqfliteFfiInit();

  const journal = SyncSchema.artistDependencyJournalTable;
  const createdAt = '2026-10-20T12:00:00.000Z';

  Map<String, Object?> row({
    String userId = 'user_1',
    String artistId = 'artist_1',
    String requestId = 'dependency_request_1',
    int revision = 1,
    String requestJson = '{"function_name":"create_artist_with_receipt"}',
  }) {
    return {
      'user_id': userId,
      'artist_id': artistId,
      'request_id': requestId,
      'mutation_revision': revision,
      'request_json': requestJson,
      'created_at': createdAt,
    };
  }

  test('fresh version 31 creates the dependency journal', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await database.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        40,
      );

      final columns = await db.rawQuery('PRAGMA table_info($journal)');

      expect(
        columns.map((column) => column['name']),
        containsAll({
          'user_id',
          'artist_id',
          'request_id',
          'mutation_revision',
          'request_json',
          'created_at',
        }),
      );

      await db.insert(journal, row());
      expect(await db.query(journal), hasLength(1));
    } finally {
      await database.close();
    }
  });

  test('version 30 upgrade preserves existing sync records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_upgrade_',
    );
    final location = '${directory.path}/sonus.db';

    final oldDatabase = await databaseFactoryFfi.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 30,
        onCreate: (db, version) async {
          await SyncSchema.createSyncOutbox(db);
          await SyncSchema.createCloudRevisionBaselines(db);
          await SyncSchema.createArtistWriteJournal(db);
        },
      ),
    );

    try {
      await oldDatabase.insert(DatabaseTables.syncOutbox, {
        'id': 'existing_outbox',
        'user_id': 'user_1',
        'entity_type': 'artist',
        'entity_id': 'artist_1',
        'operation': 'upsert',
        'created_at': createdAt,
        'updated_at': createdAt,
        'mutation_revision': 3,
      });

      await oldDatabase.insert(SyncSchema.cloudRevisionBaselinesTable, {
        'user_id': 'user_1',
        'entity_type': 'artist',
        'entity_id': 'artist_2',
        'server_revision': 5,
      });
    } finally {
      await oldDatabase.close();
    }

    final upgraded = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final db = await upgraded.database;

      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        40,
      );

      final outbox = await db.query(DatabaseTables.syncOutbox);
      expect(outbox, hasLength(1));
      expect(outbox.single['mutation_revision'], 3);

      final baselines = await db.query(SyncSchema.cloudRevisionBaselinesTable);
      expect(baselines, hasLength(1));
      expect(baselines.single['server_revision'], 5);

      await db.insert(journal, row());
      expect(await db.query(journal), hasLength(1));
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });

  test('rejects duplicate dependency requests and invalid identity', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    try {
      final db = await database.database;
      await db.insert(journal, row());

      Future<void> rejected(Map<String, Object?> candidate) async {
        await expectLater(
          db.insert(journal, candidate),
          throwsA(isA<DatabaseException>()),
        );
      }

      await rejected(row(requestId: 'another_request'));
      await rejected(row(artistId: 'artist_2'));
      await rejected(
        row(artistId: 'artist_2', requestId: 'request_2', revision: 2),
      );
      await rejected(
        row(artistId: 'artist_2', requestId: 'request_2', userId: ' '),
      );
      await rejected(
        row(artistId: 'artist_2', requestId: 'request_2', requestJson: ' '),
      );

      expect(await db.query(journal), hasLength(1));
    } finally {
      await database.close();
    }
  });

  test('dependency snapshot survives SQLite restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_restart_',
    );
    final location = '${directory.path}/sonus.db';
    const snapshot =
        '{"function_name":"create_artist_with_receipt",'
        '"request":"immutable"}';

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      await (await first.database).insert(journal, row(requestJson: snapshot));
    } finally {
      await first.close();
    }

    final reopened = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final entries = await (await reopened.database).query(journal);

      expect(entries, hasLength(1));
      expect(entries.single['request_id'], 'dependency_request_1');
      expect(entries.single['mutation_revision'], 1);
      expect(entries.single['request_json'], snapshot);
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });
}
