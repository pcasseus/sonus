import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/supabase_auth_gateway.dart';

class SupabaseClientAuthGateway implements SupabaseAuthGateway {
  SupabaseClientAuthGateway({required this.client});

  final SupabaseClient client;

  @override
  User? get currentUser => client.auth.currentUser;

  @override
  Stream<AuthState> get onAuthStateChange => client.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    required String accessToken,
  }) {
    return client.auth.signInWithIdToken(
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  @override
  Future<void> signOut() {
    return client.auth.signOut();
  }
}
