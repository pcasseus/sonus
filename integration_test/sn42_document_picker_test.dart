import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/sonus_backup_orchestrator.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';
import 'package:sonus_next/features/recovery/presentation/services/file_picker_recovery_file_picker.dart';

import '../test/support/library_seed.dart';
import 'support/device_test_root.dart';

/// Drives the real Android document picker. The system dialogs are
/// operated by the host script `sn42_picker_driver.ps1` (uiautomator),
/// which taps "Save" and the `sn42-import-…` file. Disposable emulator only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase database;

  setUp(() async {
    root = await createDeviceTestRoot('picker');
    database = AppDatabase(databasePath: path.join(root.path, 'picker.db'));
    await seedConnectedLibrary(await database.database, key: 'a');
  });

  tearDown(() async {
    await database.close();
    await deleteDeviceTestRoot(root);
  });

  Future<File> createBackup(String id) => SonusBackupOrchestrator(
    exporter: SqliteBackupExporter(appDatabase: database, generateId: () => id),
  ).createBackup(destination: File(path.join(root.path, '$id.sonusbackup')));

  testWidgets('export via the system save dialog, then import via the picker', (
    _,
  ) async {
    final backup = await createBackup('picker-export');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    const platform = MethodChannelBackupDocumentPlatform();

    // 1. Export: host taps "Save"; read-back must verify the bytes.
    final exported = await const BackupDocumentExporter().export(
      source: backup,
      suggestedName: 'sn42-import-$stamp.sonusbackup',
    );

    expect(exported.outcome, BackupExportOutcome.verified);
    expect(exported.documentUri, startsWith('content://'));

    try {
      // 2. Import: host taps the exported file in the open dialog.
      final picked = await FilePickerRecoveryFilePicker().pickBackupFile();

      expect(picked, isNotNull);
      expect(await picked!.length(), await backup.length());

      final verified = await const BackupArchiveVerifier().verify(picked);
      expect(verified.manifest.backupId, 'picker-export');
    } finally {
      // Remove only the document this test created.
      expect(await platform.deleteDocument(exported.documentUri!), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
