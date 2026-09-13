import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
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
