import '../entities/account_user.dart';

abstract interface class AccountRepository {
  AccountUser? get currentUser;

  Stream<AccountUser?> watchAuthState();

  Future<AccountUser?> signInWithGoogle();

  Future<void> signOut();
}
