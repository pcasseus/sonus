import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_library_organization_repository.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';

import '../../support/recovery_fixtures.dart';

/// SN-50 §0.6: release-level Leaked (database version 41) must not break
/// restoring backups from versions 31 to 40, which never had it.
void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_leaked_backup_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    await target.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A library with one release that is a live soundtrack EP marked as
  /// leaked, backed up by this build.
  Future<VerifiedBackupContents> currentBackup() => verifiedFixtureContents(
    directory: root,
    seed: (db) async {
      await seedConnectedLibrary(db, key: 'a');
      await db.insert(DatabaseTables.albumReleaseClassifications, {
        'album_id': 'album-a',
        'kind': 'soundtrack',
        'authority': 'manual',
        'format': 'ep',
        'format_authority': 'manual',
        'live': 1,
        'live_authority': 'manual',
        'leaked': 1,
        'created_at': fixtureTimestamp,
        'updated_at': fixtureTimestamp,
      });
    },
  );

  /// [contents] as a backup written at database [version]: tables and
  /// columns that version did not have are left out.
  Future<VerifiedBackupContents> asVersion(
    VerifiedBackupContents contents,
    int version,
  ) async {
    final missing = <String, Set<String>>{
      DatabaseTables.albumEditions: {
        if (version < 39) 'release_date_precision',
      },
      DatabaseTables.albumReleaseClassifications: {
        if (version < 41) 'leaked',
        if (version < 40) ...{
          'live',
          'live_authority',
          'live_source_reference',
        },
        if (version < 38) ...{
          'format',
          'format_authority',
          'format_source_reference',
        },
      },
    };
    final absentTables = {
      if (version < 34) ...{
        DatabaseTables.albumReleaseClassifications,
        DatabaseTables.artistProjectAssignments,
      },
      if (version < 35) DatabaseTables.artworkCrops,
    };
    final tables = {
      for (final entry in contents.backup.payload.tables.entries)
        if (!absentTables.contains(entry.key))
          entry.key: [
            for (final row in entry.value)
              {
                for (final cell in row.entries)
                  if (!(missing[entry.key]?.contains(cell.key) ?? false))
                    cell.key: cell.value,
              },
          ],
    };
    final payload = BackupDataPayload(tables: tables);
    final manifest = BackupManifest(
      backupId: 'v$version',
      createdAtUtc: DateTime.utc(2026, 10, 21),
      databaseVersion: version,
      rowCounts: {
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
    );

    final staging = Directory(path.join(root.path, 'staging-$version'));
    await staging.create();
    await File(path.join(staging.path, 'manifest.json')).writeAsString(
      jsonEncode({'manifest': manifest.toJson(), 'artwork': <Object>[]}),
    );
    await File(path.join(staging.path, 'library.json')).writeAsString(
      const BackupIntegrityCodec().encode(manifest: manifest, payload: payload),
    );
    final file = await const BackupArchiveWriter().write(
      stagingDirectory: staging,
      destination: File(path.join(root.path, 'v$version.sonusbackup')),
    );
    return const BackupArchiveVerifier().verifyAndExtract(
      backupFile: file,
      targetDirectory: Directory(path.join(root.path, 'extract-$version')),
    );
  }

  /// Checks and restores [contents] onto the target device.
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

  for (var version = 31; version <= 40; version++) {
    test('a version $version backup restores, and nothing is leaked', () async {
      final backup = await asVersion(await currentBackup(), version);
      expect(
        backup
                .backup
                .payload
                .tables[DatabaseTables.albumReleaseClassifications]
                ?.single
                .containsKey('leaked') ??
            false,
        isFalse,
      );

      await restore(backup);

      final db = await target.database;
      expect((await db.query(DatabaseTables.songs)).map((row) => row['id']), [
        'song-a',
      ]);
      final classifications = await db.query(
        DatabaseTables.albumReleaseClassifications,
      );
      expect(classifications, hasLength(version < 34 ? 0 : 1));
      for (final row in classifications) {
        expect(row['kind'], 'soundtrack');
        expect(row['live'], version < 40 ? isNull : 1);
        expect(row['leaked'], isNull);
      }
      expect(
        await SqliteLibraryOrganizationRepository(
          target,
        ).getLeakedClassifications(),
        isEmpty,
      );
    });
  }

  test('a current-version backup keeps a release marked as leaked', () async {
    final backup = await currentBackup();
    expect(backup.backup.manifest.databaseVersion, AppDatabase.databaseVersion);

    await restore(backup);

    final leaked = await SqliteLibraryOrganizationRepository(
      target,
    ).getLeakedClassifications();
    expect(leaked.map((l) => l.albumId), ['album-a']);
    final row = (await (await target.database).query(
      DatabaseTables.albumReleaseClassifications,
    )).single;
    expect(row['live'], 1);
    expect(row['format'], 'ep');
  });
}
