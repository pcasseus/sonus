import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/settings/presentation/pages/account_cloud_settings_page.dart';
import 'package:sonus_next/core/network/timed_http_client.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/models/sync_failure.dart';
import 'package:sonus_next/features/sync/application/services/automatic_sync_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/cloud_library_first_link_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_network_policy_service.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

void main() {
  testWidgets('shows signed-out sync state', (tester) async {
    final accountController = AccountController(
      repository: _FakeAccountRepository(),
    );

    final syncController = SyncController.forTesting(
      synchronize: (_) async => _successResult(),
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('settings-sync-signed-out')),
      findsOneWidget,
    );
    expect(find.text('Sign in to sync your Sonus library.'), findsOneWidget);
  });

  testWidgets('shows successful sync state and pending count', (tester) async {
    final accountController = _signedInAccountController();

    final syncController = SyncController.forTesting(
      synchronize: (_) async => _successResult(pendingAfterSync: 3),
    );

    await syncController.synchronize('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('settings-sync-card')),
      findsOneWidget,
    );
    expect(find.text('Up to date'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-sync-last-synced')),
      findsOneWidget,
    );

    final pending = tester.widget<Text>(
      find.byKey(const ValueKey<String>('settings-sync-pending')),
    );

    expect(pending.data, '3');
  });

  testWidgets('sync now triggers synchronization', (tester) async {
    var syncCalls = 0;

    final accountController = _signedInAccountController();

    final syncController = SyncController.forTesting(
      synchronize: (userId) async {
        syncCalls += 1;
        expect(userId, 'user-1');
        return _successResult();
      },
    );

    await syncController.activateUser('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    final button = find.byKey(
      const ValueKey<String>('settings-sync-now-button'),
    );

    await tester.ensureVisible(button);

    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(syncController.status, SyncStatus.success);
    expect(find.text('Up to date'), findsOneWidget);
  });

  testWidgets('shows retry state after sync failure', (tester) async {
    final accountController = _signedInAccountController();

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        throw StateError('network failure');
      },
    );

    await syncController.activateUser('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    final button = find.byKey(
      const ValueKey<String>('settings-sync-now-button'),
    );

    await tester.ensureVisible(button);

    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(syncController.status, SyncStatus.error);
    expect(find.text('Waiting to retry'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-sync-error')),
      findsOneWidget,
    );
  });

  testWidgets('a stalled sync leaves Syncing, explains, and retries', (
    tester,
  ) async {
    final accountController = _signedInAccountController();
    final stalled = Completer<SyncRunResult>();
    var attempts = 0;

    final syncController = SyncController.forTesting(
      synchronize: (_) {
        attempts++;
        return attempts == 1 ? stalled.future : Future.value(_successResult());
      },
      countPending: (_) async => 2,
    );

    await syncController.activateUser('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );
    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'real pending count');

    final run = syncController.synchronize('user-1');
    await tester.pump();
    expect(find.text('Syncing your library...'), findsOneWidget);

    stalled.completeError(
      NetworkTimeoutException(
        NetworkTimeoutPhase.response,
        const Duration(seconds: 45),
        null,
      ),
    );
    await run;
    await tester.pump();

    expect(syncController.isSyncing, isFalse);
    expect(find.text('Syncing your library...'), findsNothing);
    expect(find.text(SyncFailureKind.timeout.message), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'changes are kept');

    final retry = find.widgetWithText(FilledButton, 'Try again');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text(SyncFailureKind.timeout.message), findsNothing);
  });

  testWidgets('shows account conflict and disables sync', (tester) async {
    final accountController = _signedInAccountController();

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        throw const LocalAccountBindingConflict(
          boundUserId: 'user-old',
          requestedUserId: 'user-1',
        );
      },
    );

    await syncController.synchronize('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(find.text('Account conflict'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-sync-account-conflict')),
      findsOneWidget,
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('settings-sync-now-button')),
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('an existing cloud library waits for the choice', (tester) async {
    final accountController = _signedInAccountController();
    var granted = false;

    final syncController = SyncController.forTesting(
      synchronize: (userId) async {
        if (!granted) throw const SyncNeedsCloudLibraryChoice();
        return SyncRunResult(
          userId: userId,
          startedAt: DateTime.utc(2026, 10, 25),
          completedAt: DateTime.utc(2026, 10, 25, 0, 0, 1),
          claimedUnownedCount: 0,
          pendingBeforePush: 0,
          pulledRecordCount: 0,
          pendingAfterSync: 0,
        );
      },
      grantCloudLibrary: (_) async => granted = true,
    );

    await syncController.synchronize('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: _wifiPolicy(),
    );

    coordinator.updateUserId('user-1');

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(find.text('Waiting for your choice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-sync-cloud-choice')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('settings-sync-now-button')),
          )
          .onPressed,
      isNull,
    );

    final bring = find.byKey(
      const ValueKey<String>('settings-sync-bring-cloud-library'),
    );
    await tester.ensureVisible(bring);
    await tester.pumpAndSettle();
    await tester.tap(bring);
    await tester.pumpAndSettle();

    expect(granted, isTrue);
    expect(find.text('Up to date'), findsOneWidget);
    expect(bring, findsNothing);
  });

  testWidgets('mobile-data consent can allow sync', (tester) async {
    var mobileAllowed = false;
    var syncCalls = 0;

    final accountController = _signedInAccountController();

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        syncCalls += 1;
        return _successResult();
      },
    );

    await syncController.activateUser('user-1');

    final policy = SyncNetworkPolicyService.forTesting(
      checkConnectivity: () async => [ConnectivityResult.mobile],
      getBool: (_) async => mobileAllowed ? true : null,
      setBool: (key, value) async {
        expect(key, SyncNetworkPolicyService.mobileDataAllowedPreferenceKey);
        mobileAllowed = value;
      },
      remove: (_) async {
        mobileAllowed = false;
      },
    );

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: policy,
    );

    coordinator.updateUserId('user-1');

    await coordinator.trigger();

    expect(coordinator.mobileConsentRequired, isTrue);
    expect(syncCalls, 0);

    await tester.pumpWidget(
      _buildTestApp(
        accountController: accountController,
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    final consent = find.byKey(
      const ValueKey<String>('settings-sync-mobile-consent'),
    );

    expect(consent, findsOneWidget);

    final allowButton = find.byKey(
      const ValueKey<String>('settings-sync-allow-mobile'),
    );

    await tester.ensureVisible(allowButton);

    await tester.pumpAndSettle();
    await tester.tap(allowButton);
    await tester.pumpAndSettle();

    expect(mobileAllowed, isTrue);
    expect(syncCalls, 1);
    expect(coordinator.mobileConsentRequired, isFalse);
    expect(syncController.status, SyncStatus.success);
  });
  testWidgets('after choosing Wi-Fi only, mobile data can still be allowed', (
    tester,
  ) async {
    bool? mobileAllowed = false;
    var syncCalls = 0;

    final syncController = SyncController.forTesting(
      synchronize: (_) async {
        syncCalls += 1;
        return _successResult();
      },
    );
    await syncController.activateUser('user-1');

    final coordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: SyncNetworkPolicyService.forTesting(
        checkConnectivity: () async => [ConnectivityResult.mobile],
        getBool: (_) async => mobileAllowed,
        setBool: (key, value) async {
          expect(key, SyncNetworkPolicyService.mobileDataAllowedPreferenceKey);
          mobileAllowed = value;
        },
        remove: (_) async {
          mobileAllowed = null;
        },
      ),
    );
    coordinator.updateUserId('user-1');
    await coordinator.trigger();

    expect(coordinator.networkAccess, SyncNetworkAccess.mobileDenied);
    expect(syncCalls, 0);

    await tester.pumpWidget(
      _buildTestApp(
        accountController: _signedInAccountController(),
        syncController: syncController,
        coordinator: coordinator,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('settings-sync-wifi-only')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-sync-mobile-consent')),
      findsNothing,
    );

    final allow = find.byKey(
      const ValueKey<String>('settings-sync-allow-mobile-later'),
    );
    await tester.ensureVisible(allow);
    await tester.pumpAndSettle();
    await tester.tap(allow);
    await tester.pumpAndSettle();

    expect(mobileAllowed, isTrue);
    expect(syncCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('settings-sync-wifi-only')),
      findsNothing,
    );
  });

  testWidgets('explains what cloud sync covers from the sync contract', (
    tester,
  ) async {
    final syncController = SyncController.forTesting(
      synchronize: (_) async => _successResult(),
    );
    await tester.pumpWidget(
      _buildTestApp(
        accountController: _signedInAccountController(),
        syncController: syncController,
        coordinator: AutomaticSyncCoordinator(
          syncController: syncController,
          networkPolicy: _wifiPolicy(),
        ),
      ),
    );

    final synced = find.byKey(
      const ValueKey<String>('settings-sync-coverage-synced'),
    );
    await tester.scrollUntilVisible(
      synced,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.descendant(
        of: synced,
        matching: find.text('Artists, Albums, Album editions, Songs, Artwork'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('settings-sync-coverage-not-synced'),
        ),
        matching: find.textContaining('Playlists'),
      ),
      findsOneWidget,
    );
  });
}

Widget _buildTestApp({
  required AccountController accountController,
  required SyncController syncController,
  required AutomaticSyncCoordinator coordinator,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AccountController>.value(value: accountController),
      ChangeNotifierProvider<SyncController>.value(value: syncController),
      ChangeNotifierProvider<AutomaticSyncCoordinator>.value(
        value: coordinator,
      ),
    ],
    child: const MaterialApp(home: AccountCloudSettingsPage()),
  );
}

AccountController _signedInAccountController() {
  return AccountController(
    repository: _FakeAccountRepository(
      currentUser: const AccountUser(
        id: 'user-1',
        email: 'person@example.com',
        displayName: 'Person Example',
        avatarUrl: null,
      ),
    ),
  );
}

SyncNetworkPolicyService _wifiPolicy() {
  return SyncNetworkPolicyService.forTesting(
    checkConnectivity: () async => [ConnectivityResult.wifi],
    getBool: (_) async => null,
    setBool: (_, _) async {},
    remove: (_) async {},
  );
}

SyncRunResult _successResult({int pendingAfterSync = 0}) {
  final startedAt = DateTime.utc(2026, 10, 6, 18);
  final completedAt = DateTime.utc(2026, 10, 6, 18, 1);

  return SyncRunResult(
    userId: 'user-1',
    startedAt: startedAt,
    completedAt: completedAt,
    claimedUnownedCount: 0,
    pendingBeforePush: 0,
    pulledRecordCount: 0,
    pendingAfterSync: pendingAfterSync,
  );
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this._currentUser});

  AccountUser? _currentUser;

  final StreamController<AccountUser?> _controller =
      StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get currentUser => _currentUser;

  @override
  Stream<AccountUser?> watchAuthState() => _controller.stream;

  @override
  Future<AccountUser?> signInWithGoogle() async => _currentUser;

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}
