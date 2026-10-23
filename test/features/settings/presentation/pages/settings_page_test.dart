import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/presentation/pages/appearance_settings_page.dart';
import 'package:sonus_next/features/settings/presentation/pages/settings_page.dart';

void main() {
  testWidgets('shows unavailable account state without controller', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    expect(
      find.byKey(const ValueKey<String>('settings-account-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('shows signed-out account state', (tester) async {
    final repository = _FakeAccountRepository();
    final controller = AccountController(repository: repository);

    await tester.pumpWidget(_buildTestApp(controller));

    expect(
      find.byKey(const ValueKey<String>('settings-account-signed-out')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-google-sign-in-button')),
      findsOneWidget,
    );
  });

  testWidgets('shows signed-in account identity', (tester) async {
    final repository = _FakeAccountRepository(
      currentUser: const AccountUser(
        id: 'user-1',
        email: 'person@example.com',
        displayName: 'Person Example',
        avatarUrl: null,
      ),
    );
    final controller = AccountController(repository: repository);

    await tester.pumpWidget(_buildTestApp(controller));

    expect(
      find.byKey(const ValueKey<String>('settings-account-signed-in')),
      findsOneWidget,
    );
    expect(find.text('Person Example'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-sign-out-button')),
      findsOneWidget,
    );
  });

  testWidgets('sign-in button enters loading state', (tester) async {
    final signInCompleter = Completer<AccountUser?>();
    final repository = _FakeAccountRepository(
      signInHandler: () => signInCompleter.future,
    );
    final controller = AccountController(repository: repository);

    await tester.pumpWidget(_buildTestApp(controller));

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-google-sign-in-button')),
    );
    await tester.pump();

    expect(find.text('Signing in...'), findsOneWidget);

    signInCompleter.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('shows sign-in error', (tester) async {
    final repository = _FakeAccountRepository(
      signInHandler: () async {
        throw StateError('sign-in failed');
      },
    );
    final controller = AccountController(repository: repository);

    await tester.pumpWidget(_buildTestApp(controller));

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-google-sign-in-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-account-error')),
      findsOneWidget,
    );
  });

  testWidgets('opens listening history from settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-listening-history')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('listening-history-page')),
      findsOneWidget,
    );
  });
  testWidgets('opens blacklisted songs from settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    final blacklistedSongsTile = find.byKey(
      const ValueKey<String>('settings-blacklisted-songs'),
    );

    await tester.scrollUntilVisible(
      blacklistedSongsTile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(blacklistedSongsTile);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('blacklisted-songs-page')),
      findsOneWidget,
    );
  });
  testWidgets('opens Metadata Intelligence settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    final tile = find.byKey(
      const ValueKey<String>('settings-metadata-intelligence'),
    );

    // The tile starts below the list's build window.
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-metadata-intelligence')),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('metadata-intelligence-settings-page')),
      findsOneWidget,
    );
  });
  testWidgets('sign-out returns to signed-out state', (tester) async {
    final repository = _FakeAccountRepository(
      currentUser: const AccountUser(
        id: 'user-1',
        email: 'person@example.com',
        displayName: 'Person Example',
        avatarUrl: null,
      ),
    );
    final controller = AccountController(repository: repository);

    await tester.pumpWidget(_buildTestApp(controller));

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-sign-out-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('settings-account-signed-out')),
      findsOneWidget,
    );
  });

  testWidgets('opens Appearance settings showing the active theme', (
    tester,
  ) async {
    final appearance = AppearanceController(
      store: AppearancePreferencesStore.forTesting(
        getString: (key) async => null,
        setString: (key, value) async {},
      ),
    );
    addTearDown(appearance.dispose);
    await appearance.load();
    await appearance.selectTheme(SonusThemeId.afterHours);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceController>.value(
        value: appearance,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    final tile = find.byKey(const ValueKey<String>('settings-appearance'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.descendant(
        of: tile,
        matching: find.text('After Hours · Street Bold'),
      ),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceSettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('appearance-preview')),
      findsOneWidget,
    );
  });
}

Widget _buildTestApp(AccountController controller) {
  return ChangeNotifierProvider<AccountController>.value(
    value: controller,
    child: const MaterialApp(home: SettingsPage()),
  );
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this._currentUser, this._signInHandler});

  AccountUser? _currentUser;
  final Future<AccountUser?> Function()? _signInHandler;

  final StreamController<AccountUser?> _authController =
      StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get currentUser => _currentUser;

  @override
  Stream<AccountUser?> watchAuthState() => _authController.stream;

  @override
  Future<AccountUser?> signInWithGoogle() async {
    final handler = _signInHandler;

    if (handler != null) {
      final user = await handler();
      _currentUser = user;
      return user;
    }

    return _currentUser;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}
