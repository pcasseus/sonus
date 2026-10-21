import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';

void main() {
  sqfliteFfiInit();

  test(
    'independent writer is blocked until export transaction finishes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sonus_backup_isolation_',
      );
      final databasePath = '${directory.path}/sonus.db';

      final appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      Database? writer;
      final artistsRead = Completer<void>();
      final resumeExport = Completer<void>();

      try {
        final reader = await appDatabase.database;

        writer = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );

        expect(identical(reader, writer), isFalse);

        // Fail quickly instead of waiting ten seconds on SQLITE_BUSY.
        await writer.execute('PRAGMA busy_timeout = 100');

        final exporter = SqliteBackupExporter(
          appDatabase: appDatabase,
          generateId: () => 'isolated-backup',
          now: () => DateTime.utc(2026, 10, 21),
          afterTableRead: (table) async {
            if (table == DatabaseTables.artists) {
              artistsRead.complete();
              await resumeExport.future;
            }
          },
        );

        final exportFuture = exporter.export();

        await artistsRead.future;

        try {
          // An independent write cannot begin while the export owns
          // its SQLite transaction under this locking configuration.
          await expectLater(
            writer.transaction((transaction) async {
              await transaction.insert(DatabaseTables.artists, {
                'id': 'blocked-artist',
                'name': 'Blocked Artist',
                'canonical_name': 'blocked artist',
                'created_at': '2026-10-21T00:00:00.000Z',
                'updated_at': '2026-10-21T00:00:00.000Z',
              });
            }),
            throwsA(isA<DatabaseException>()),
          );
        } finally {
          resumeExport.complete();
        }

        final exported = await exportFuture;

        expect(exported.payload.tables[DatabaseTables.artists], isEmpty);
        expect(exported.payload.tables[DatabaseTables.playlists], isEmpty);

        // Once the original export finishes, a write through the
        // independent connection must succeed.
        await writer.transaction((transaction) async {
          const timestamp = '2026-10-21T00:00:00.000Z';

          await transaction.insert(DatabaseTables.artists, {
            'id': 'concurrent-artist',
            'name': 'Concurrent Artist',
            'canonical_name': 'concurrent artist',
            'created_at': timestamp,
            'updated_at': timestamp,
          });

          await transaction.insert(DatabaseTables.playlists, {
            'id': 'concurrent-playlist',
            'name': 'Concurrent Playlist',
            'created_at': timestamp,
            'updated_at': timestamp,
          });
        });

        final laterExport = await SqliteBackupExporter(
          appDatabase: appDatabase,
          generateId: () => 'later-backup',
          now: () => DateTime.utc(2026, 10, 21),
        ).export();

        expect(
          laterExport.payload.tables[DatabaseTables.artists]!.single['id'],
          'concurrent-artist',
        );
        expect(
          laterExport.payload.tables[DatabaseTables.playlists]!.single['id'],
          'concurrent-playlist',
        );
        expect(laterExport.payload.totalRows, 2);
      } finally {
        if (!resumeExport.isCompleted) {
          resumeExport.complete();
        }
        await writer?.close();
        await appDatabase.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
