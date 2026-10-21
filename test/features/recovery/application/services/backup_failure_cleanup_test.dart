import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_failure.dart';
import 'package:sonus_next/features/recovery/application/models/backup_manifest.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';
import 'package:sonus_next/features/recovery/application/services/backup_artwork_inventory_service.dart';
import 'package:sonus_next/features/recovery/application/services/backup_artwork_staging_service.dart';
import 'package:sonus_next/features/recovery/application/services/backup_integrity_codec.dart';
import 'package:sonus_next/features/recovery/application/services/backup_json_codec.dart';
import 'package:sonus_next/features/recovery/application/services/backup_publication.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';

import '../../../../support/test_only_backup_publication.dart';

class _InjectedFailure implements Exception {
  const _InjectedFailure(this.stage);

  final String stage;
}

class _FailingExporter extends SqliteBackupExporter {
  _FailingExporter({required super.appDatabase});

  @override
  Future<SqliteBackupExportResult> export() async {
    throw const _InjectedFailure('export');
  }
}

class _FailingStaging extends BackupArtworkStagingService {
  const _FailingStaging();

  @override
  Future<void> stage({
    required List<BackupArtworkItem> inventory,
    required Directory stagingDirectory,
  }) async {
    await stagingDirectory.create(recursive: true);
    await File(path.join(stagingDirectory.path, 'partial')).writeAsBytes([1]);
    throw const _InjectedFailure('staging');
  }
}

class _FailingCodec extends BackupIntegrityCodec {
  const _FailingCodec();

  @override
  String encode({
    required BackupManifest manifest,
    required BackupDataPayload payload,
  }) {
    throw const _InjectedFailure('documents');
  }
}

class _FailingWriter extends BackupArchiveWriter {
  const _FailingWriter();

  @override
  Future<File> write({
    required Directory stagingDirectory,
    required File destination,
  }) async {
    await destination.writeAsBytes([1, 2, 3]);
    throw const _InjectedFailure('packaging');
  }
}

class _FailingVerifier extends BackupArchiveVerifier {
  const _FailingVerifier();

  @override
  Future<DecodedBackup> verify(File backupFile) async {
    throw const _InjectedFailure('verification');
  }
}

class _FailingPublication implements BackupPublication {
  const _FailingPublication();

  @override
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  }) async {
    throw const _InjectedFailure('publication');
  }
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase appDatabase;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_backup_cleanup_');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  SqliteBackupExporter exporter() => SqliteBackupExporter(
    appDatabase: appDatabase,
    generateId: () => 'cleanup-backup',
    now: () => DateTime.utc(2026, 10, 21),
  );

  Future<void> insertArtwork(String id, String filePath) async {
    const timestamp = '2026-10-21T00:00:00.000Z';
    final db = await appDatabase.database;

    await db.insert(DatabaseTables.artworkAssets, {
      'id': id,
      'file_path': filePath,
      'normalized_path': filePath.toLowerCase(),
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  }

  Future<void> expectCleanFailure(
    SonusBackupOrchestrator orchestrator,
    String stage,
  ) async {
    final destination = File(path.join(root.path, 'failed.sonusbackup'));
    final stages = <BackupStage>[];

    await expectLater(
      orchestrator.createBackup(destination: destination, onProgress: stages.add),
      throwsA(isA<_InjectedFailure>().having((e) => e.stage, 'stage', stage)),
    );

    expect(await destination.exists(), isFalse);
    expect(stages, isNot(contains(BackupStage.published)));

    final leftovers = await root.list().toList();
    expect(
      leftovers.where(
        (entity) => path.basename(entity.path).startsWith('.sonus_'),
      ),
      isEmpty,
      reason: 'Temporary data remained after a $stage failure.',
    );
  }

  const testPublisher = VerifiedBackupPublisher(
    publication: TestOnlyBackupPublication(),
  );

  group('failure at every stage leaves no backup or temporary data', () {
    test('database export', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: _FailingExporter(appDatabase: appDatabase),
          publisher: testPublisher,
        ),
        'export',
      );
    });

    test('artwork staging', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: exporter(),
          artworkStaging: const _FailingStaging(),
          publisher: testPublisher,
        ),
        'staging',
      );
    });

    test('document writing', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: exporter(),
          integrityCodec: const _FailingCodec(),
          publisher: testPublisher,
        ),
        'documents',
      );
    });

    test('packaging', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: exporter(),
          publisher: const VerifiedBackupPublisher(
            writer: _FailingWriter(),
            publication: TestOnlyBackupPublication(),
          ),
        ),
        'packaging',
      );
    });

    test('verification', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: exporter(),
          publisher: const VerifiedBackupPublisher(
            verifier: _FailingVerifier(),
            publication: TestOnlyBackupPublication(),
          ),
        ),
        'verification',
      );
    });

    test('publication', () async {
      await expectCleanFailure(
        SonusBackupOrchestrator(
          exporter: exporter(),
          publisher: const VerifiedBackupPublisher(
            publication: _FailingPublication(),
          ),
        ),
        'publication',
      );
    });
  });

  test('reports progress stages in order on success', () async {
    final stages = <BackupStage>[];

    await SonusBackupOrchestrator(
      exporter: exporter(),
      publisher: testPublisher,
    ).createBackup(
      destination: File(path.join(root.path, 'ok.sonusbackup')),
      onProgress: stages.add,
    );

    expect(stages, BackupStage.values);
  });

  test('reports every missing artwork file in one typed failure', () async {
    final present = File(path.join(root.path, 'present.jpg'));
    await present.writeAsBytes([1, 2, 3]);

    await insertArtwork('artwork-b', path.join(root.path, 'gone-b.jpg'));
    await insertArtwork('artwork-present', present.path);
    await insertArtwork('artwork-a', path.join(root.path, 'gone-a.jpg'));

    final destination = File(path.join(root.path, 'missing.sonusbackup'));

    await expectLater(
      SonusBackupOrchestrator(
        exporter: exporter(),
        publisher: testPublisher,
      ).createBackup(destination: destination),
      throwsA(
        isA<BackupException>()
            .having((e) => e.code, 'code', BackupFailureCode.missingArtwork)
            .having((e) => e.artworkIds, 'artworkIds', [
              'artwork-a',
              'artwork-b',
            ]),
      ),
    );

    expect(await destination.exists(), isFalse);
    expect(await present.readAsBytes(), [1, 2, 3]);
  });

  test('artwork changed after inventory is a typed failure', () async {
    final cover = File(path.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([1, 2, 3]);

    final inventory = await const BackupArtworkInventoryService().build(
      BackupDataPayload(
        tables: {
          for (final table in (await exporter().export()).payload.tables.keys)
            table: table == DatabaseTables.artworkAssets
                ? [
                    {'id': 'artwork-1', 'file_path': cover.path},
                  ]
                : <Map<String, Object?>>[],
        },
      ),
    );

    await cover.writeAsBytes([3, 2, 1]);

    await expectLater(
      const BackupArtworkStagingService().stage(
        inventory: inventory,
        stagingDirectory: Directory(path.join(root.path, 'staging')),
      ),
      throwsA(
        isA<BackupException>().having(
          (e) => e.code,
          'code',
          BackupFailureCode.artworkChanged,
        ),
      ),
    );
  });
}
