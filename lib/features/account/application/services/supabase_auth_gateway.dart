import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SupabaseAuthGateway {
  User? get currentUser;

  Stream<AuthState> get onAuthStateChange;

  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    required String accessToken,
  });

  Future<void> signOut();
}
