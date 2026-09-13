import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/google_auth_gateway.dart';
import '../../application/services/supabase_auth_gateway.dart';
import '../../domain/entities/account_user.dart';
import '../../domain/repositories/account_repository.dart';
import '../mappers/supabase_account_user_mapper.dart';

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository({
    required this._supabaseAuthGateway,
    required this._googleAuthGateway,
  });

  final SupabaseAuthGateway _supabaseAuthGateway;
  final GoogleAuthGateway _googleAuthGateway;

  @override
  AccountUser? get currentUser {
    final user = _supabaseAuthGateway.currentUser;

    if (user == null) {
      return null;
    }

    return SupabaseAccountUserMapper.fromUser(user);
  }

  @override
  Stream<AccountUser?> watchAuthState() {
    return _supabaseAuthGateway.onAuthStateChange.map((state) {
      final user = state.session?.user;

      if (user == null) {
        return null;
      }

      return SupabaseAccountUserMapper.fromUser(user);
    });
  }

  @override
  Future<AccountUser?> signInWithGoogle() async {
    final credential = await _googleAuthGateway.signIn();

    if (credential == null) {
      return null;
    }

    final response = await _supabaseAuthGateway.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: credential.idToken,
      accessToken: credential.accessToken,
    );

    final user = response.user;

    if (user == null) {
      throw StateError(
        'Supabase authentication completed without returning a user.',
      );
    }

    return SupabaseAccountUserMapper.fromUser(user);
  }

  @override
  Future<void> signOut() async {
    Object? supabaseError;
    StackTrace? supabaseStackTrace;

    try {
      await _supabaseAuthGateway.signOut();
    } catch (error, stackTrace) {
      supabaseError = error;
      supabaseStackTrace = stackTrace;
    }

    try {
      await _googleAuthGateway.signOut();
    } catch (_) {
      if (supabaseError == null) {
        rethrow;
      }
    }

    if (supabaseError != null) {
      Error.throwWithStackTrace(supabaseError, supabaseStackTrace!);
    }
  }
}
