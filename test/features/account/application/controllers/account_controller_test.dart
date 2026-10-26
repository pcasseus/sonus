import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_failure.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';

void main() {
  group('AccountController', () {
    test('starts with repository current user', () {
      const user = AccountUser(
        id: 'user_1',
        email: 'user@example.com',
        displayName: 'User',
      );

      final repository = _FakeAccountRepository(currentUser: user);
      final controller = AccountController(repository: repository);

      expect(controller.user, same(user));
      expect(controller.isSignedIn, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('initialize listens for auth state changes', () async {
      final repository = _FakeAccountRepository();
      final controller = AccountController(repository: repository);

      controller.initialize();

      const user = AccountUser(id: 'user_2', email: 'listener@example.com');

      repository.emitAuthState(user);

      await Future<void>.delayed(Duration.zero);

      expect(controller.user, same(user));
      expect(controller.isSignedIn, isTrue);

      repository.emitAuthState(null);

      await Future<void>.delayed(Duration.zero);

      expect(controller.user, isNull);
      expect(controller.isSignedIn, isFalse);

      controller.dispose();
      await repository.dispose();
    });

    test('signInWithGoogle stores signed-in user', () async {
      const user = AccountUser(
        id: 'user_3',
        email: 'google@example.com',
        displayName: 'Google User',
      );

      final repository = _FakeAccountRepository(signInResult: user);
      final controller = AccountController(repository: repository);

      final result = await controller.signInWithGoogle();

      expect(result, isTrue);
      expect(controller.user, same(user));
      expect(controller.isSignedIn, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(repository.signInCallCount, 1);

      controller.dispose();
    });

    test('signInWithGoogle returns false when sign-in is cancelled', () async {
      final repository = _FakeAccountRepository();
      final controller = AccountController(repository: repository);

      final result = await controller.signInWithGoogle();

      expect(result, isFalse);
      expect(controller.user, isNull);
      expect(controller.isSignedIn, isFalse);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('signInWithGoogle captures repository failure', () async {
      final repository = _FakeAccountRepository(
        signInError: StateError('Google sign-in failed'),
      );

      final controller = AccountController(repository: repository);

      final result = await controller.signInWithGoogle();

      expect(result, isFalse);
      expect(controller.user, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isA<StateError>());
      expect(controller.hasError, isTrue);

      controller.dispose();
    });

    test('signOut clears signed-in user', () async {
      const user = AccountUser(id: 'user_4', email: 'signed-in@example.com');

      final repository = _FakeAccountRepository(currentUser: user);
      final controller = AccountController(repository: repository);

      final result = await controller.signOut();

      expect(result, isTrue);
      expect(controller.user, isNull);
      expect(controller.isSignedIn, isFalse);
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(repository.signOutCallCount, 1);

      controller.dispose();
    });

    test('signOut preserves user when repository fails', () async {
      const user = AccountUser(
        id: 'user_5',
        email: 'still-signed-in@example.com',
      );

      final repository = _FakeAccountRepository(
        currentUser: user,
        signOutError: StateError('Sign-out failed'),
      );

      final controller = AccountController(repository: repository);

      final result = await controller.signOut();

      expect(result, isFalse);
      expect(controller.user, same(user));
      expect(controller.isSignedIn, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isA<StateError>());

      controller.dispose();
    });
  });

  group('SN-49 sign-in states', () {
    const user = AccountUser(id: 'user_1', email: 'user@example.com');

    test('a failed sign-in says what kind of failure it was', () async {
      for (final kind in AccountFailureKind.values) {
        final repository = _FakeAccountRepository(
          signInError: AccountFailure(kind, cause: StateError('cause')),
        );
        final controller = AccountController(repository: repository);

        expect(await controller.signInWithGoogle(), isFalse);
        expect(controller.failureKind, kind);
        expect(controller.isSignedIn, isFalse);

        controller.dispose();
        await repository.dispose();
      }
    });

    test('an unclassified error is reported as unknown', () async {
      final repository = _FakeAccountRepository(signInError: Exception('x'));
      final controller = AccountController(repository: repository);

      await controller.signInWithGoogle();
      expect(controller.failureKind, AccountFailureKind.unknown);

      controller.dispose();
      await repository.dispose();
    });

    test(
      'cancelling is not an error and leaves the person signed out',
      () async {
        final repository = _FakeAccountRepository();
        final controller = AccountController(repository: repository);

        expect(await controller.signInWithGoogle(), isFalse);
        expect(controller.hasError, isFalse);
        expect(controller.failureKind, isNull);
        expect(controller.isSignedIn, isFalse);

        controller.dispose();
        await repository.dispose();
      },
    );

    test('a saved session is restored after a restart, offline too', () async {
      // The account service's saved session is all a restart reads; no
      // network call is made to know who is signed in.
      final repository = _FakeAccountRepository(currentUser: user);
      final controller = AccountController(repository: repository)
        ..initialize();

      expect(controller.isSignedIn, isTrue);
      expect(controller.user, same(user));
      expect(repository.signInCallCount, 0);

      controller.dispose();
      await repository.dispose();
    });

    test('signed out, signed in, failed, then signed in again', () async {
      final repository = _FakeAccountRepository(
        signInError: const AccountFailure(AccountFailureKind.offline),
      );
      final controller = AccountController(repository: repository)
        ..initialize();
      final seen = <String>[];
      controller.addListener(
        () => seen.add(
          controller.isLoading
              ? 'loading'
              : controller.isSignedIn
              ? 'in'
              : controller.hasError
              ? 'failed'
              : 'out',
        ),
      );

      await controller.signInWithGoogle();
      repository.emitAuthState(user);
      await Future<void>.delayed(Duration.zero);
      repository.emitAuthState(null);
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['loading', 'failed', 'in', 'out']);
      expect(controller.hasError, isFalse, reason: 'a new state clears it');

      controller.dispose();
      await repository.dispose();
    });
  });
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({
    this._currentUser,
    this.signInResult,
    this.signInError,
    this.signOutError,
  });

  AccountUser? _currentUser;
  final AccountUser? signInResult;
  final Object? signInError;
  final Object? signOutError;

  final StreamController<AccountUser?> _authStateController =
      StreamController<AccountUser?>.broadcast();

  int signInCallCount = 0;
  int signOutCallCount = 0;

  @override
  AccountUser? get currentUser => _currentUser;

  @override
  Stream<AccountUser?> watchAuthState() {
    return _authStateController.stream;
  }

  @override
  Future<AccountUser?> signInWithGoogle() async {
    signInCallCount++;

    final error = signInError;

    if (error != null) {
      throw error;
    }

    _currentUser = signInResult;

    return signInResult;
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;

    final error = signOutError;

    if (error != null) {
      throw error;
    }

    _currentUser = null;
  }

  void emitAuthState(AccountUser? user) {
    _currentUser = user;
    _authStateController.add(user);
  }

  Future<void> dispose() {
    return _authStateController.close();
  }
}
