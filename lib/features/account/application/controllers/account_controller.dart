import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../domain/entities/account_failure.dart';
import '../../domain/entities/account_user.dart';
import '../../domain/repositories/account_repository.dart';

class AccountController extends ChangeNotifier {
  AccountController({required AccountRepository repository})
    : _repository = repository,
      _user = repository.currentUser;

  final AccountRepository _repository;

  AccountUser? _user;
  bool _isLoading = false;
  Object? _error;
  StreamSubscription<AccountUser?>? _authStateSubscription;

  AccountUser? get user => _user;

  bool get isSignedIn => _user != null;

  bool get isLoading => _isLoading;

  Object? get error => _error;

  bool get hasError => _error != null;

  /// What the last failed sign-in needs from the person; null without one.
  AccountFailureKind? get failureKind => switch (_error) {
    null => null,
    AccountFailure(:final kind) => kind,
    _ => AccountFailureKind.unknown,
  };

  void initialize() {
    if (_authStateSubscription != null) {
      return;
    }

    _user = _repository.currentUser;

    _authStateSubscription = _repository.watchAuthState().listen(
      (user) {
        _user = user;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error;
        notifyListeners();
      },
    );

    notifyListeners();
  }

  Future<bool> signInWithGoogle() async {
    if (_isLoading) {
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _repository.signInWithGoogle();

      if (user == null) {
        return false;
      }

      _user = user;

      return true;
    } catch (error) {
      _error = error;
      _log('Sign-in failed', error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signOut() async {
    if (_isLoading) {
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _repository.signOut();
      _user = null;

      return true;
    } catch (error) {
      _error = error;
      _log('Sign-out failed', error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The kind and type of failure only: never tokens, names or emails.
  static void _log(String message, Object error) {
    final kind = error is AccountFailure ? error.kind.name : 'unknown';
    final cause = error is AccountFailure ? error.cause : error;
    developer.log(
      '$message ($kind, ${cause.runtimeType})',
      name: 'sonus.account',
      level: 900,
    );
  }

  @override
  void dispose() {
    unawaited(_authStateSubscription?.cancel());
    super.dispose();
  }
}
