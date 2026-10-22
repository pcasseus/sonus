import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/app/app_restart_scope.dart';
import 'package:sonus_next/features/recovery/application/controllers/backup_restore_controller.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_overview.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/models/restore_preflight.dart';
import 'package:sonus_next/features/recovery/application/models/restore_result.dart';
import 'package:sonus_next/features/recovery/application/services/backup_document_exporter.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/presentation/pages/backup_restore_page.dart';

import '../../../../support/fake_recovery_service.dart';

void main() {
  late FakeRecoveryService service;
  late BackupRestoreController controller;
  late int resumes;

  setUp(() {
    service = FakeRecoveryService();
    resumes = 0;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    controller = BackupRestoreController(
      service: service,
      onSyncMayResume: () => resumes++,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppRestartScope(
        child: ChangeNotifierProvider<BackupRestoreController?>.value(
          value: controller,
          child: const MaterialApp(home: BackupRestorePage()),
        ),
      ),
    );

    await controller.initialize();
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  Future<void> scrollTo(WidgetTester tester, String value) async {
    await tester.scrollUntilVisible(
      key(value),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
  }

  group('sync hold', () {
    test('startup check runs before the overview is loaded', () async {
      final controller = BackupRestoreController(service: service);
      await controller.initialize();

      expect(service.calls.take(2), ['startup', 'overview']);
      controller.dispose();
    });

    testWidgets('explains the hold and offers no way to bypass it', (
      tester,
    ) async {
      service.overview = fakeOverview(
        hold: const RecoveryHoldOverview(
          active: true,
          phase: RecoverySyncHoldPhase.assessmentRequired,
          findings: [
            RecoverySyncFinding.accountUnconfirmed,
            RecoverySyncFinding.cloudLibraryDiverged,
          ],
          divergedTables: ['songs', 'artists'],
        ),
      );

      await pumpPage(tester);

      expect(key('recovery-sync-hold'), findsOneWidget);
      expect(find.text('Cloud sync is paused'), findsOneWidget);
      expect(find.textContaining('keep working'), findsOneWidget);
      expect(key('recovery-sync-hold-reason-0'), findsOneWidget);
      expect(key('recovery-sync-hold-reason-1'), findsOneWidget);
      expect(find.textContaining('Songs, Artists'), findsOneWidget);
      expect(find.textContaining('cannot be overridden'), findsOneWidget);

      // There is deliberately no resume/override control.
      expect(find.textContaining('Resume'), findsNothing);
      expect(find.textContaining('anyway'), findsNothing);
      expect(resumes, 0, reason: 'sync must not be resumed while held');
    });

    testWidgets('check again only re-runs the conclusive assessment', (
      tester,
    ) async {
      service.overview = fakeOverview(
        hold: const RecoveryHoldOverview(
          active: true,
          findings: [RecoverySyncFinding.cloudLibraryDiverged],
        ),
      );
      await pumpPage(tester);

      // The re-check now proves consistency and the hold is gone.
      service.overview = fakeOverview();
      await tester.tap(key('recovery-sync-hold-recheck'));
      await tester.pumpAndSettle();

      expect(service.calls, contains('recheck'));
      expect(key('recovery-sync-hold'), findsNothing);
      expect(resumes, 1);
    });

    testWidgets('a failed startup check keeps sync paused and says why', (
      tester,
    ) async {
      service.startupError = const FileSystemException('unavailable');

      await pumpPage(tester);

      expect(key('recovery-sync-hold'), findsOneWidget);
      expect(find.textContaining('interrupted restore'), findsOneWidget);
      expect(resumes, 0);
    });

    testWidgets('an interrupted restore is shown as needing attention', (
      tester,
    ) async {
      service.overview = fakeOverview(
        hold: const RecoveryHoldOverview(
          active: true,
          phase: RecoverySyncHoldPhase.restoring,
          findings: [RecoverySyncFinding.preRestoreStateMissing],
        ),
      );

      await pumpPage(tester);

      expect(find.textContaining('A restore did not finish'), findsOneWidget);
      expect(find.textContaining('was interrupted'), findsOneWidget);
    });

    testWidgets('no hold card when sync is free; sync may resume', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(key('recovery-sync-hold'), findsNothing);
      expect(resumes, 1);
    });
  });

  group('restore', () {
    testWidgets('preview, confirmation gating, and completion', (
      tester,
    ) async {
      service.onPreview = (file) => RestorePreview(
        backupFile: file,
        preflight: fakePreflight(cloudLinked: true),
        plan: fakePlan(songs: 12, removed: 3, missingAudio: 12),
      );

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();

      expect(key('recovery-restore-preview'), findsOneWidget);
      expect(tester.widget<Text>(key('recovery-plan-songs')).data, '12');
      expect(tester.widget<Text>(key('recovery-plan-removed')).data, '3');
      expect(key('recovery-sync-will-pause'), findsOneWidget);
      expect(key('recovery-safety-notice'), findsOneWidget);

      await scrollTo(tester, 'recovery-start-restore');
      await tester.tap(key('recovery-start-restore'));
      await tester.pumpAndSettle();

      // Replace stays disabled until the user acknowledges.
      final replace = tester.widget<FilledButton>(key('recovery-confirm-replace'));
      expect(replace.onPressed, isNull);

      await tester.tap(key('recovery-confirm-acknowledge'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-replace'));
      await tester.pumpAndSettle();

      expect(service.calls, contains('restore'));
      expect(key('recovery-restore-complete'), findsOneWidget);
      expect(key('recovery-complete-safety'), findsOneWidget);
      expect(key('recovery-complete-sync-held'), findsOneWidget);
      expect(key('recovery-reload-app'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation restores nothing', (
      tester,
    ) async {
      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'recovery-start-restore');
      await tester.tap(key('recovery-start-restore'));
      await tester.pumpAndSettle();

      await tester.tap(key('recovery-confirm-acknowledge'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-cancel'));
      await tester.pumpAndSettle();

      expect(service.calls, isNot(contains('restore')));
      expect(key('recovery-restore-preview'), findsOneWidget);

      await tester.tap(key('recovery-cancel-restore'));
      await tester.pumpAndSettle();
      expect(key('recovery-restore-preview'), findsNothing);
      expect(service.calls, isNot(contains('restore')));
    });

    testWidgets('a cancelled file picker leaves everything unchanged', (
      tester,
    ) async {
      service.pickedBackup = null;

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();

      expect(service.calls, isNot(contains('preview')));
      expect(key('recovery-restore-preview'), findsNothing);
    });

    testWidgets('a blocked backup explains why and cannot be restored', (
      tester,
    ) async {
      service.onPreview = (file) => RestorePreview(
        backupFile: file,
        preflight: fakePreflight(
          blockers: const [
            RestoreBlocker.pendingSyncWork,
            RestoreBlocker.insufficientStorage,
          ],
        ),
        plan: null,
      );

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();

      expect(key('recovery-blocker-pendingSyncWork'), findsOneWidget);
      expect(key('recovery-blocker-insufficientStorage'), findsOneWidget);
      expect(key('recovery-start-restore'), findsNothing);
    });

    testWidgets('shows progress and blocks navigation while restoring', (
      tester,
    ) async {
      service.restoreGate = Completer<void>();

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'recovery-start-restore');
      await tester.tap(key('recovery-start-restore'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-acknowledge'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-replace'));
      await tester.pump();
      await tester.pump();

      expect(key('recovery-restoring'), findsOneWidget);
      expect(find.text('Restoring your library…'), findsOneWidget);
      expect(find.byType(PopScope), findsWidgets);

      service.restoreGate!.complete();
      await tester.pumpAndSettle();
      expect(key('recovery-restore-complete'), findsOneWidget);
    });

    testWidgets('a failed restore reports the verified rollback', (
      tester,
    ) async {
      service.onRestore = (_) async => throw const RestoreFailedException(
        stage: RestoreStage.restoringDatabase,
        cause: 'disk',
        rollbackVerified: true,
        syncHoldPreserved: false,
      );

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-choose-backup');
      await tester.tap(key('recovery-choose-backup'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'recovery-start-restore');
      await tester.tap(key('recovery-start-restore'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-acknowledge'));
      await tester.pumpAndSettle();
      await tester.tap(key('recovery-confirm-replace'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(key('recovery-error'), -200,
          scrollable: find.byType(Scrollable).first);
      expect(key('recovery-error'), findsOneWidget);
      expect(find.textContaining('left exactly as it was'), findsOneWidget);
      expect(key('recovery-restore-complete'), findsNothing);
    });

    test('the controller refuses a restore without acknowledgement', () async {
      final controller = BackupRestoreController(service: service);
      await controller.previewBackup(File('/x.sonusbackup'));

      expect(
        () => controller.confirmRestore(acknowledged: false),
        throwsStateError,
      );
      expect(service.calls, isNot(contains('restore')));
      controller.dispose();
    });
  });

  group('backup and private backups', () {
    for (final (outcome, expected, kept) in [
      (BackupExportOutcome.verified, 'saved and verified', false),
      (BackupExportOutcome.cancelled, 'No backup was saved', false),
      (BackupExportOutcome.writtenUnverified, 'private copy was kept', true),
      (BackupExportOutcome.failed, 'private copy was kept', true),
    ]) {
      testWidgets('reports a ${outcome.name} export honestly', (tester) async {
        service.backupResult = BackupCreationResult(
          backupId: 'b',
          export: BackupExportResult(outcome: outcome),
          privateCopy: kept ? File('/private/b.sonusbackup') : null,
        );

        await pumpPage(tester);
        await tester.tap(key('recovery-create-backup'));
        await tester.pumpAndSettle();

        expect(find.textContaining(expected), findsOneWidget);
        if (outcome != BackupExportOutcome.verified) {
          expect(find.textContaining('saved and verified'), findsNothing);
        }
      });
    }

    testWidgets('distinguishes private safety backups from exports', (
      tester,
    ) async {
      service.overview = fakeOverview(
        privateBackups: [
          PrivateBackupFile(
            file: File('/private/safety/pre.sonusbackup'),
            kind: PrivateBackupKind.safetyBackup,
            byteLength: 2048,
            modifiedAt: DateTime.utc(2026, 10, 21),
          ),
          PrivateBackupFile(
            file: File('/private/backups/b.sonusbackup'),
            kind: PrivateBackupKind.unverifiedExportCopy,
            byteLength: 4096,
            modifiedAt: DateTime.utc(2026, 10, 20),
          ),
        ],
      );

      await pumpPage(tester);
      await scrollTo(tester, 'recovery-private-backup-1');

      expect(find.text('Private backups on this device'), findsOneWidget);
      expect(find.textContaining('lost if Sonus is uninstalled'), findsOneWidget);
      expect(find.text('Safety backup (before a restore)'), findsOneWidget);
      expect(find.text('Backup not verified off-device'), findsOneWidget);

      await scrollTo(tester, 'recovery-private-backup-menu-0');
      await tester.tap(key('recovery-private-backup-menu-0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save a copy…'));
      await tester.pumpAndSettle();

      expect(service.calls, contains('export-copy'));
      expect(key('recovery-copy-result'), findsOneWidget);
    });
  });

  testWidgets('relinks audio from a chosen folder', (tester) async {
    service.overview = fakeOverview(missingAudio: 12);

    await pumpPage(tester);
    await scrollTo(tester, 'recovery-relink-audio');
    expect(
      tester.widget<Text>(key('recovery-missing-audio')).data,
      contains('12 of 20'),
    );

    await tester.tap(key('recovery-relink-audio'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('relink:/music'));
    expect(find.textContaining('Relinked 7 songs'), findsOneWidget);
  });

  testWidgets('reload after restore rebuilds the app subtree', (tester) async {
    var builds = 0;

    await tester.pumpWidget(
      AppRestartScope(
        child: StatefulBuilder(
          builder: (context, _) {
            builds++;
            return MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AppRestartScope.restart(context),
                  child: const Text('reload'),
                ),
              ),
            );
          },
        ),
      ),
    );

    final before = builds;
    await tester.tap(find.text('reload'));
    await tester.pumpAndSettle();

    expect(builds, greaterThan(before));
  });
}
