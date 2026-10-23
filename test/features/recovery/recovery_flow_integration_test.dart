import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/recovery/application/controllers/backup_restore_controller.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_overview.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_audio_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_fingerprint_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/recovery/application/services/restore_journal_store.dart';
import 'package:sonus_next/features/recovery/application/services/verified_backup_publisher.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';

import '../../support/recovery_fixtures.dart';
import '../../support/test_only_backup_publication.dart';

/// "Downloads" folder standing in for the Android document provider.
class _DownloadsFolder implements BackupDocumentPlatform {
  _DownloadsFolder(this.root);

  final Directory root;
  bool refuseReads = false;

  File file(String uri) => File(path.join(root.path, uri.split('/').last));

  @override
  Future<String?> createDocument(String suggestedName) async {
    await File(path.join(root.path, suggestedName)).create(exclusive: true);
    return 'content://downloads/$suggestedName';
  }

  @override
  Future<int> writeDocument({required File source, required String uri}) async {
    await source.copy(file(uri).path);
    return file(uri).length();
  }

  @override
  Future<({String sha256, int length})?> readBackDocument(String uri) async {
    if (refuseReads) return null;
    final bytes = await file(uri).readAsBytes();
    return (sha256: sha256.convert(bytes).toString(), length: bytes.length);
  }

  @override
  Future<bool> deleteDocument(String uri) async {
    await file(uri).delete();
    return true;
  }
}

class _Picker implements RecoveryFilePicker {
  File? backup;

  @override
  Future<File?> pickBackupFile() async => backup;

  @override
  Future<String?> pickMusicFolder() async => null;
}

void main() {
  sqfliteFfiInit();

  late Directory root;
  late Directory support;
  late Directory recovery;
  late Directory downloads;
  late AppDatabase database;
  late _DownloadsFolder documents;
  late _Picker picker;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_recovery_flow_');
    support = Directory(path.join(root.path, 'support'));
    recovery = Directory(path.join(support.path, 'sonus', 'recovery'));
    downloads = Directory(path.join(root.path, 'Downloads'));
    await downloads.create(recursive: true);
    await recovery.create(recursive: true);
    database = fileAppDatabase(root, 'sonus_next.db');
    documents = _DownloadsFolder(downloads);
    picker = _Picker();
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A fresh gate and service model one app launch.
  ({RecoverySyncGate gate, BackupRestoreController controller, List<int> resumes})
  launch() {
    final gate = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => recovery),
      requiresStartupCheck: true,
    );
    final resumes = <int>[];

    final controller = BackupRestoreController(
      service: DefaultRecoveryService(
        appDatabase: database,
        gate: gate,
        recoveryDirectory: () async => recovery,
        artworkDirectory: () async =>
            Directory(path.join(support.path, 'sonus', 'artwork')),
        supportDirectory: () async => support,
        picker: picker,
        stopPlayback: () async {},
        relink: (_) async => throw UnimplementedError(),
        exporter: BackupDocumentExporter(platform: documents),
        publisher: const VerifiedBackupPublisher(
          publication: TestOnlyBackupPublication(),
        ),
        storageProbe: null,
      ),
      onSyncMayResume: () => resumes.add(1),
    );
    addTearDown(controller.dispose);

    return (gate: gate, controller: controller, resumes: resumes);
  }

  Future<bool> syncAllowed(RecoverySyncGate gate) async {
    try {
      await gate.guard(() async {});
      return true;
    } on SyncHeldForRecovery {
      return false;
    }
  }

  Future<void> bindCloudAccount() async {
    final db = await database.database;
    await db.insert(DatabaseTables.localAccountBinding, {
      'id': 1,
      'user_id': 'user-1',
      'bound_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
    await db.insert(SyncSchema.cloudRevisionBaselinesTable, {
      'user_id': 'user-1',
      'entity_type': 'artist',
      'entity_id': 'artist-a',
      'server_revision': 1,
    });
  }

  test('sync is blocked at launch until the recovery check runs', () async {
    final app = launch();

    expect(await syncAllowed(app.gate), isFalse);

    await app.controller.initialize();

    expect(await syncAllowed(app.gate), isTrue);
    expect(app.resumes, [1]);
  });

  test('an interrupted restore is recovered at launch before sync', () async {
    await bindCloudAccount();
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a', userId: 'user-1');
    final before = await snapshotDatabase(db);

    // State left by a restore killed before its transaction committed.
    await RecoverySyncHoldStore(directory: () async => recovery).write(
      RecoverySyncHold(
        holdId: 'killed',
        backupId: 'killed',
        createdAtUtc: DateTime.utc(2026, 10, 21),
        phase: RecoverySyncHoldPhase.restoring,
        backupAccountIds: const {'user-1'},
        preRestore: await const RecoveryFingerprintService().capture(db),
      ),
    );
    final orphan = File(
      path.join(support.path, 'sonus', 'artwork', 'artwork_restorekilledn0.jpg'),
    );
    await orphan.create(recursive: true);
    await RestoreJournalStore(directory: () async => recovery).write(
      RestoreJournal(
        sessionId: 'killed',
        extractionDirectory: path.join(recovery.path, '.sonus_restore_killed'),
        reservedTokens: const ['restorekilledn0'],
        createdFiles: [orphan.path],
      ),
    );

    final app = launch();
    expect(await syncAllowed(app.gate), isFalse);

    await app.controller.initialize();

    expect(await orphan.exists(), isFalse);
    expect(await snapshotDatabase(db), before);
    expect(app.controller.overview!.hold.active, isFalse);
    expect(await syncAllowed(app.gate), isTrue);
    expect(app.resumes, [1]);
  });

  test('back up, save off-device, restore on a cloud-linked device, stay held', () async {
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a', userId: 'user-1', songTitle: 'Original');
    await bindCloudAccount();

    var app = launch();
    await app.controller.initialize();

    // Back up and save to "Downloads", verified by read-back.
    await app.controller.createBackup();
    final created = app.controller.backupResult!;
    expect(created.export.outcome, BackupExportOutcome.verified);
    expect(created.privateCopy, isNull);
    expect(app.controller.overview!.history.lastBackup!.exportVerified, isTrue);

    final saved = (await downloads.list().toList()).whereType<File>().single;

    // Library changes after the backup.
    await db.update(
      DatabaseTables.songs,
      {'title': 'Edited later'},
      where: 'id = ?',
      whereArgs: ['song-a'],
    );

    // Choose the saved file, preview, then cancel: nothing changes.
    picker.backup = saved;
    await app.controller.chooseBackupToRestore();
    expect(app.controller.preview!.canRestore, isTrue);
    final beforeCancel = await snapshotDatabase(db);
    app.controller.cancelRestore();
    expect(await snapshotDatabase(db), beforeCancel);

    // Preview again and confirm.
    await app.controller.chooseBackupToRestore();
    await app.controller.confirmRestore(acknowledged: true);

    final result = app.controller.restoreResult!;
    expect(result.safetyBackup, isNotNull);
    expect(
      (await db.query(DatabaseTables.songs)).single['title'],
      'Original',
    );

    // The library differs from what the cloud baseline was built for.
    expect(result.syncHeld, isTrue);
    expect(await syncAllowed(app.gate), isFalse);

    // Relaunch: the hold persists and is explained; the safety backup is
    // listed as a private, on-device backup.
    app = launch();
    await app.controller.initialize();

    final overview = app.controller.overview!;
    expect(overview.hold.active, isTrue);
    expect(
      overview.hold.findings,
      contains(RecoverySyncFinding.cloudLibraryDiverged),
    );
    expect(overview.history.lastRestore!.syncHeld, isTrue);
    expect(
      overview.privateBackups.map((b) => b.kind),
      contains(PrivateBackupKind.safetyBackup),
    );
    expect(await syncAllowed(app.gate), isFalse);
    expect(app.resumes, isEmpty);

    // Re-checking cannot release an inconclusive hold.
    await app.controller.recheckSyncHold();
    expect(await syncAllowed(app.gate), isFalse);
    expect(app.resumes, isEmpty);

    // Offline features keep working: the library is readable.
    final audio = await RecoveryAudioStatusService(appDatabase: database).status();
    expect(audio.totalSongs, 1);
  });

  test('an unverifiable export keeps a private copy and is not success', () async {
    documents.refuseReads = true;
    await seedConnectedLibrary(await database.database, key: 'a');

    final app = launch();
    await app.controller.initialize();
    await app.controller.createBackup();

    final created = app.controller.backupResult!;
    expect(created.export.outcome, BackupExportOutcome.writtenUnverified);
    expect(await created.privateCopy!.exists(), isTrue);
    expect(app.controller.overview!.history.lastBackup, isNull);
    expect(
      app.controller.overview!.privateBackups.single.kind,
      PrivateBackupKind.unverifiedExportCopy,
    );
  });
}
