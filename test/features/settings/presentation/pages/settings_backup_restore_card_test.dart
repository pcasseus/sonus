import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/recovery/application/controllers/backup_restore_controller.dart';
import 'package:sonus_next/features/recovery/application/models/recovery_overview.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_assessment_service.dart';
import 'package:sonus_next/features/recovery/presentation/pages/backup_restore_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/settings_page.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';

import '../../../../support/fake_recovery_service.dart';

void main() {
  Finder key(String value) => find.byKey(ValueKey<String>(value));

  Future<BackupRestoreController> pumpSettings(
    WidgetTester tester, {
    RecoveryHoldOverview hold = RecoveryHoldOverview.none,
    SyncController? syncController,
    AccountController? accountController,
    AutomaticSyncCoordinator? coordinator,
  }) async {
    final service = FakeRecoveryService()..overview = fakeOverview(hold: hold);
    final controller = BackupRestoreController(service: service);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BackupRestoreController?>.value(
            value: controller,
          ),
          ChangeNotifierProvider<AccountController?>.value(
            value: accountController,
          ),
          ChangeNotifierProvider<SyncController?>.value(value: syncController),
          ChangeNotifierProvider<AutomaticSyncCoordinator?>.value(
            value: coordinator,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    return controller;
  }

  testWidgets('offers Backup & Restore and opens the page', (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(key('settings-backup-restore'), 200);
    expect(
      tester.widget<Text>(key('settings-backup-restore-subtitle')).data,
      contains('restore it on a new device'),
    );

    await tester.tap(key('settings-backup-restore'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupRestorePage), findsOneWidget);
  });

  testWidgets('the card flags a recovery sync hold', (tester) async {
    await pumpSettings(
      tester,
      hold: const RecoveryHoldOverview(
        active: true,
        findings: [RecoverySyncFinding.cloudLibraryDiverged],
      ),
    );

    await tester.scrollUntilVisible(key('settings-backup-restore'), 200);
    expect(
      tester.widget<Text>(key('settings-backup-restore-subtitle')).data,
      'Cloud sync is paused for recovery review.',
    );
  });

  testWidgets('the sync card explains a recovery hold', (tester) async {
    final syncController = SyncController.forTesting(
      synchronize: (_) async =>
          throw const SyncHeldForRecovery(SyncHoldReason.assessmentRequired),
    );
    await syncController.synchronize('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: SyncNetworkPolicyService.forTesting(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        getBool: (_) async => null,
        setBool: (_, _) async {},
        remove: (_) async {},
      ),
    );
    coordinator.updateUserId('user-1');

    await pumpSettings(
      tester,
      syncController: syncController,
      coordinator: coordinator,
      accountController: AccountController(repository: _SignedInRepository()),
    );

    expect(find.text('Paused for recovery review'), findsOneWidget);
    expect(key('settings-sync-recovery-hold'), findsOneWidget);
    expect(key('settings-sync-error'), findsNothing);
  });
}

class _SignedInRepository implements AccountRepository {
  final _controller = StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get currentUser => const AccountUser(
    id: 'user-1',
    email: 'person@example.com',
    displayName: 'Person Example',
    avatarUrl: null,
  );

  @override
  Stream<AccountUser?> watchAuthState() => _controller.stream;

  @override
  Future<AccountUser?> signInWithGoogle() async => currentUser;

  @override
  Future<void> signOut() async {}
}
