import 'package:google_sign_in/google_sign_in.dart';

import '../../application/services/google_auth_credential.dart';
import '../../application/services/google_auth_gateway.dart';

class GoogleSignInAuthGateway implements GoogleAuthGateway {
  GoogleSignInAuthGateway({
    required String serverClientId,
    GoogleSignIn? googleSignIn,
  }) : _serverClientId = serverClientId.trim(),
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  static const List<String> _authorizationScopes = <String>[
    'openid',
    'email',
    'profile',
  ];

  final String _serverClientId;
  final GoogleSignIn _googleSignIn;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (_serverClientId.isEmpty) {
      throw StateError('Google server client ID is not configured.');
    }

    await _googleSignIn.initialize(serverClientId: _serverClientId);

    _isInitialized = true;
  }

  @override
  Future<GoogleAuthCredential?> signIn() async {
    await initialize();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError(
        'Interactive Google authentication is not supported on this platform.',
      );
    }

    try {
      final account = await _googleSignIn.authenticate(
        scopeHint: _authorizationScopes,
      );

      final idToken = account.authentication.idToken?.trim();

      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google authentication did not return an ID token.');
      }

      final authorization =
          await account.authorizationClient.authorizationForScopes(
            _authorizationScopes,
          ) ??
          await account.authorizationClient.authorizeScopes(
            _authorizationScopes,
          );

      final accessToken = authorization.accessToken.trim();

      if (accessToken.isEmpty) {
        throw StateError(
          'Google authorization did not return an access token.',
        );
      }

      return GoogleAuthCredential(idToken: idToken, accessToken: accessToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }

      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    await initialize();
    await _googleSignIn.signOut();
  }
}
