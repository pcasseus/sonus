import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

void main() {
  test('does nothing while signed out', () async {
    var syncCalls = 0;

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        syncCalls++;
        return _result();
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(connectivity: [ConnectivityResult.wifi]),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    await coordinator.trigger();

    expect(syncCalls, 0);
  });

  test('automatically syncs signed-in user over Wi-Fi', () async {
    final users = <String>[];

    final syncController = SyncController.forTesting(
      synchronize: (userId) async {
        users.add(userId);
        return _result(userId: userId);
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(connectivity: [ConnectivityResult.wifi]),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId(' user-1 ');
    await coordinator.trigger();

    expect(users, ['user-1']);
    expect(coordinator.networkAccess, SyncNetworkAccess.allowed);
    expect(coordinator.mobileConsentRequired, isFalse);
  });

  test('waits for consent on first mobile-data connection', () async {
    var syncCalls = 0;

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        syncCalls++;
        return _result();
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(
        connectivity: [ConnectivityResult.mobile],
        mobileAllowed: null,
      ),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');
    await coordinator.trigger();

    expect(syncCalls, 0);
    expect(coordinator.mobileConsentRequired, isTrue);
    expect(coordinator.networkAccess, SyncNetworkAccess.mobileConsentRequired);
  });

  test('allowing mobile data persists choice and syncs immediately', () async {
    bool? mobileAllowed;
    var syncCalls = 0;

    final policy = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (_) async => mobileAllowed,
      setBool: (_, value) async {
        mobileAllowed = value;
      },
      remove: (_) async {
        mobileAllowed = null;
      },
    );

    final syncController = SyncController.forTesting(
      synchronize: (userId) async {
        syncCalls++;
        return _result(userId: userId);
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: policy,
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');

    await coordinator.trigger();

    expect(coordinator.mobileConsentRequired, isTrue);

    await coordinator.allowMobileDataAndSync();

    expect(mobileAllowed, isTrue);
    expect(syncCalls, 1);
    expect(coordinator.mobileConsentRequired, isFalse);
  });

  test('denying mobile data prevents synchronization', () async {
    bool? mobileAllowed;
    var syncCalls = 0;

    final policy = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (_) async => mobileAllowed,
      setBool: (_, value) async {
        mobileAllowed = value;
      },
      remove: (_) async {},
    );

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        syncCalls++;
        return _result();
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: policy,
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');

    await coordinator.denyMobileData();
    await coordinator.trigger();

    expect(mobileAllowed, isFalse);
    expect(syncCalls, 0);
    expect(coordinator.networkAccess, SyncNetworkAccess.mobileDenied);
  });

  test('offline state does not become a sync error', () async {
    final syncController = SyncController.forTesting(
      synchronize: (_) async => _result(),
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(connectivity: [ConnectivityResult.none]),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');
    await coordinator.trigger();

    expect(coordinator.networkAccess, SyncNetworkAccess.offline);
    expect(syncController.status, SyncStatus.idle);
    expect(syncController.lastError, isNull);
  });

  test('account conflict prevents later automatic retries', () async {
    var calls = 0;

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        calls++;

        throw const LocalAccountBindingConflict(
          boundUserId: 'user-1',
          requestedUserId: 'user-2',
        );
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(connectivity: [ConnectivityResult.wifi]),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-2');

    await coordinator.trigger();
    await coordinator.trigger();

    expect(calls, 1);
    expect(syncController.hasAccountConflict, isTrue);
  });

  test('sign out resets sync state', () async {
    final syncController = SyncController.forTesting(
      synchronize: (userId) async =>
          _result(userId: userId, pendingAfterSync: 2),
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _policy(connectivity: [ConnectivityResult.wifi]),
    );

    addTearDown(syncController.dispose);
    addTearDown(coordinator.dispose);

    coordinator.updateUserId('user-1');
    await coordinator.trigger();

    expect(syncController.currentUserId, 'user-1');

    coordinator.updateUserId(null);

    expect(coordinator.userId, isNull);
    expect(syncController.currentUserId, isNull);
    expect(syncController.status, SyncStatus.idle);
  });
}

SyncNetworkPolicyService _policy({
  required List<ConnectivityResult> connectivity,
  bool? mobileAllowed,
}) {
  return SyncNetworkPolicyService.forTesting(
    checkConnectivity: () async => connectivity,
    getBool: (_) async => mobileAllowed,
    setBool: (_, _) async {},
    remove: (_) async {},
  );
}

SyncRunResult _result({String userId = 'user-1', int pendingAfterSync = 0}) {
  final time = DateTime.utc(2026, 10, 6, 12);

  return SyncRunResult(
    userId: userId,
    startedAt: time,
    completedAt: time,
    claimedUnownedCount: 0,
    pendingBeforePush: 0,
    pulledRecordCount: 0,
    pendingAfterSync: pendingAfterSync,
  );
}
