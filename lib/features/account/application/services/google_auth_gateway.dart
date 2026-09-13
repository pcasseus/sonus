import 'google_auth_credential.dart';

abstract interface class GoogleAuthGateway {
  Future<GoogleAuthCredential?> signIn();

  Future<void> signOut();
}
