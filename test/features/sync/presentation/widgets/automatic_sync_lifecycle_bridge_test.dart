import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/presentation/widgets/automatic_sync_lifecycle_bridge.dart';

void main() {
  testWidgets('syncs current signed-in user after startup', (tester) async {
    final calls = <String>[];

    final accountController = AccountController(
      repository: _FakeAccountRepository(
        currentUser: const AccountUser(id: 'user-1'),
      ),
    )..initialize();

    final syncController = SyncController.forTesting(
      synchronize: (userId) async {
        calls.add(userId);
        return _result(userId);
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    addTearDown(accountController.dispose);
    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountController>.value(
            value: accountController,
          ),
          ChangeNotifierProvider<SyncController>.value(value: syncController),
          ChangeNotifierProvider<AutomaticSyncCoordinator>.value(
            value: coordinator,
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AutomaticSyncLifecycleBridge(child: Text('child')),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(calls, contains('user-1'));
  });

  testWidgets('resets when signed out', (tester) async {
    final repository = _FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1'),
    );

    final accountController = AccountController(repository: repository)
      ..initialize();

    final syncController = SyncController.forTesting(
      synchronize: (userId) async => _result(userId),
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    addTearDown(accountController.dispose);
    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountController>.value(
            value: accountController,
          ),
          ChangeNotifierProvider<SyncController>.value(value: syncController),
          ChangeNotifierProvider<AutomaticSyncCoordinator>.value(
            value: coordinator,
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AutomaticSyncLifecycleBridge(child: Text('child')),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await accountController.signOut();
    await tester.pump();
    await tester.pump();

    expect(coordinator.userId, isNull);
    expect(syncController.currentUserId, isNull);
    expect(syncController.status, SyncStatus.idle);
  });
}

SyncNetworkPolicyService _wifiPolicy() {
  return SyncNetworkPolicyService.forTesting(
    checkConnectivity: () async => [ConnectivityResult.wifi],
    getBool: (_) async => null,
    setBool: (_, _) async {},
    remove: (_) async {},
  );
}

SyncRunResult _result(String userId) {
  final time = DateTime.utc(2026, 10, 6, 12);

  return SyncRunResult(
    userId: userId,
    startedAt: time,
    completedAt: time,
    claimedUnownedCount: 0,
    pendingBeforePush: 0,
    pulledRecordCount: 0,
    pendingAfterSync: 0,
  );
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.currentUser});

  @override
  AccountUser? currentUser;

  @override
  Stream<AccountUser?> watchAuthState() {
    return const Stream<AccountUser?>.empty();
  }

  @override
  Future<AccountUser?> signInWithGoogle() async {
    return currentUser;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}
