import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';

import 'test_only_backup_publication.dart';

export 'library_seed.dart';

AppDatabase fileAppDatabase(Directory directory, String name) => AppDatabase(
  databaseFactory: databaseFactoryFfi,
  databasePath: path.join(directory.path, name),
);

/// Writes a real verified backup of [source] into [directory].
Future<File> createFixtureBackup({
  required AppDatabase source,
  required Directory directory,
  String backupId = 'fixture-backup',
  String fileName = 'fixture.sonusbackup',
}) {
  return SonusBackupOrchestrator(
    exporter: SqliteBackupExporter(
      appDatabase: source,
      generateId: () => backupId,
      now: () => DateTime.utc(2026, 10, 21),
    ),
    publisher: const VerifiedBackupPublisher(
      publication: TestOnlyBackupPublication(),
    ),
  ).createBackup(destination: File(path.join(directory.path, fileName)));
}

/// Builds a backup from [seed] and returns its verified extraction.
Future<VerifiedBackupContents> verifiedFixtureContents({
  required Directory directory,
  required Future<void> Function(DatabaseExecutor db) seed,
  String backupId = 'fixture-backup',
}) async {
  // A separate file database keeps the backup source isolated from the
  // restore target, whatever sqflite does with shared in-memory handles.
  final source = fileAppDatabase(directory, 'source_$backupId.db');

  try {
    await seed(await source.database);

    final backup = await createFixtureBackup(
      source: source,
      directory: directory,
      backupId: backupId,
      fileName: '$backupId.sonusbackup',
    );

    return await const BackupArchiveVerifier().verifyAndExtract(
      backupFile: backup,
      targetDirectory: Directory(
        path.join(directory.path, '.sonus_restore_$backupId'),
      ),
    );
  } finally {
    await source.close();
  }
}
