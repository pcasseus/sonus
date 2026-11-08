// App Update 1.2: restoring an older backup never brings back what was
// permanently deleted (or merged) on this device. Disposable data only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';

import '../../support/recovery_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_deletion_restore_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    await target.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> restore(VerifiedBackupContents contents) async {
    final preflight = await RestorePreflightService(
      appDatabase: target,
    ).assess(contents);
    expect(preflight.blockers, isEmpty);
    final db = await target.database;
    await db.transaction(
      (transaction) => const SqliteRestoreExecutor().apply(
        transaction: transaction,
        backup: contents.backup,
        artworkPaths: const {},
      ),
    );
  }

  Future<int> count(String table, [String where = '1']) async =>
      (await (await target.database).rawQuery(
            'SELECT COUNT(*) AS n FROM $table WHERE $where',
          )).single['n']!
          as int;

  test('a deleted song stays deleted through a restore', () async {
    final backup = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a', songTitle: 'Deleted');
        await seedConnectedLibrary(db, key: 'b', week: 1, songTitle: 'Kept');
      },
    );
    await restore(backup);
    expect(await count(DatabaseTables.songs), 2);
    final historyOfA = await count(
      DatabaseTables.qualifiedPlays,
      "song_id = 'song-a'",
    );
    expect(historyOfA, greaterThan(0));

    final service = PermanentDeletionService(
      appDatabase: target,
      isCloudLinked: (_) async => false,
      changes: LibraryChangeSignal(),
    );
    await service.delete(
      await service.preview(const PermanentDeletionTarget.song('song-a')),
    );
    expect(await count(DatabaseTables.songs, "id = 'song-a'"), 0);

    // The backup still holds song A, its history, chart rows and Moments.
    await restore(backup);

    expect(await count(DatabaseTables.songs, "id = 'song-a'"), 0);
    expect(await count(DatabaseTables.songs, "id = 'song-b'"), 1);
    expect(
      await count(DatabaseTables.playbackSessions, "song_id = 'song-a'"),
      0,
    );
    expect(await count(DatabaseTables.qualifiedPlays, "song_id = 'song-a'"), 0);
    expect(
      await count(
        DatabaseTables.chartMomentEvents,
        "entity_id = 'song-a' OR related_entity_id = 'song-a'",
      ),
      0,
    );
    expect(await count(DatabaseTables.chartEntries, "entity_id = 'song-a'"), 0);
    expect(await count(DatabaseTables.playlistItems, "song_id = 'song-a'"), 0);
    // Song B came back whole.
    expect(
      await count(DatabaseTables.qualifiedPlays, "song_id = 'song-b'"),
      greaterThan(0),
    );
    expect(await count(DatabaseTables.playlistItems, "song_id = 'song-b'"), 1);
    // The ledger survived the restore.
    expect(
      await count(
        DatabaseTables.libraryDeletionLedger,
        "entity_type = 'song' AND entity_id = 'song-a'",
      ),
      1,
    );
  });

  test('a merged duplicate stays merged through a restore', () async {
    final backup = await verifiedFixtureContents(
      directory: root,
      seed: (db) async {
        await seedConnectedLibrary(db, key: 'a');
        // A duplicate of release A from an older import: same owner, title
        // and recording, no history of its own.
        Future<void> copy(
          String table,
          String id,
          Map<String, Object?> set,
        ) async {
          final row = (await db.query(
            table,
            where: 'id = ?',
            whereArgs: [id],
          )).single;
          await db.insert(table, {...row, ...set});
        }

        await copy(DatabaseTables.albums, 'album-a', {
          'id': 'album-dup',
          'created_at': '2026-11-01T00:00:00.000Z',
        });
        await copy(DatabaseTables.albumEditions, 'edition-a', {
          'id': 'edition-dup',
          'album_id': 'album-dup',
        });
        await copy(DatabaseTables.songs, 'song-a', {
          'id': 'song-dup',
          'album_id': 'album-dup',
          'album_edition_id': 'edition-dup',
        });
      },
    );
    await restore(backup);
    final report = await DuplicateAlbumReconciliationService(
      appDatabase: target,
      changes: LibraryChangeSignal(),
    ).reconcile();
    expect(report.merged.single.duplicateAlbumId, 'album-dup');
    final plays = await count(DatabaseTables.qualifiedPlays);

    await restore(backup);

    expect(await count(DatabaseTables.albums, "id = 'album-dup'"), 0);
    expect(await count(DatabaseTables.songs, "id = 'song-dup'"), 0);
    expect(await count(DatabaseTables.albums, "id = 'album-a'"), 1);
    expect(await count(DatabaseTables.qualifiedPlays), plays);
  });
}
