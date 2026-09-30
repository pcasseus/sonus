import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/app/account_sync_ownership_bridge.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';

void main() {
  testWidgets('attaches ownership for current signed-in user', (tester) async {
    final calls = <String>[];

    final accountRepository = _FakeAccountRepository(
      currentUser: const AccountUser(id: ' user-1 ', email: 'user@example.com'),
    );

    final accountController = AccountController(repository: accountRepository)
      ..initialize();

    addTearDown(accountController.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountController>.value(
        value: accountController,
        child: AccountSyncOwnershipBridge(
          database: null,
          attachUnownedOverride: (userId) async {
            calls.add(userId);
          },
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('child'),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(calls, ['user-1']);
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('does nothing when neither database nor override is available', (
    tester,
  ) async {
    final accountRepository = _FakeAccountRepository(
      currentUser: const AccountUser(id: 'user-1', email: 'user@example.com'),
    );

    final accountController = AccountController(repository: accountRepository)
      ..initialize();

    addTearDown(accountController.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AccountController>.value(
        value: accountController,
        child: const AccountSyncOwnershipBridge(
          database: null,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text('child'),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('child'), findsOneWidget);
  });
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
