// SN-49: the Account card says plainly whether sign-in is available, and
// after a failure, what to do. Sonus works without an account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/application/config/account_bootstrapper.dart';
import 'package:sonus_next/features/account/application/config/account_environment_config.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_failure.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/settings/presentation/widgets/settings/settings_account_card.dart';

class _Repository implements AccountRepository {
  _Repository({this.error});

  final Object? error;

  @override
  AccountUser? get currentUser => null;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  Future<AccountUser?> signInWithGoogle() async {
    final error = this.error;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  Future<void> pump(WidgetTester tester, AccountController? controller) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsAccountCard(controller: controller)),
        ),
      );

  testWidgets('a build without account settings says so and keeps working', (
    tester,
  ) async {
    await pump(tester, null);

    expect(
      find.byKey(const ValueKey<String>('settings-account-unavailable')),
      findsOneWidget,
    );
    expect(
      find.textContaining('built without the account settings'),
      findsOneWidget,
    );
    expect(find.textContaining('works fully on this device'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  test('without settings, no account service is started', () async {
    for (final config in const [
      AccountEnvironmentConfig(
        supabaseUrl: '',
        supabasePublishableKey: '',
        googleWebClientId: '',
      ),
      AccountEnvironmentConfig(
        supabaseUrl: 'https://example.invalid',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '',
      ),
    ]) {
      final result = await AccountBootstrapper.initialize(config);
      expect(result.repository, isNull);
    }
  });

  for (final (kind, expected) in [
    (AccountFailureKind.offline, 'Check your connection'),
    (AccountFailureKind.googleSetup, 'registered for the key this build'),
    (AccountFailureKind.interrupted, 'interrupted before it finished'),
    (AccountFailureKind.serverRejected, "account service didn't accept"),
    (AccountFailureKind.unknown, 'Sign-in failed. Please try again.'),
  ]) {
    testWidgets('a ${kind.name} failure says what to do', (tester) async {
      final controller = AccountController(
        repository: _Repository(error: AccountFailure(kind)),
      );
      addTearDown(controller.dispose);
      await pump(tester, controller);

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('settings-account-error')),
            )
            .data,
        contains(expected),
      );
      expect(
        find.text('Sign in with Google'),
        findsOneWidget,
        reason: 'the person can try again',
      );
    });
  }

  testWidgets('cancelling shows no error', (tester) async {
    final controller = AccountController(repository: _Repository());
    addTearDown(controller.dispose);
    await pump(tester, controller);

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-error')),
      findsNothing,
    );
  });
}
