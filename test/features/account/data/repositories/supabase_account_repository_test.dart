import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/account/application/services/google_auth_credential.dart';
import 'package:sonus_next/features/account/application/services/google_auth_gateway.dart';
import 'package:sonus_next/features/account/application/services/supabase_auth_gateway.dart';
import 'package:sonus_next/features/account/data/repositories/supabase_account_repository.dart';

void main() {
  group('SupabaseAccountRepository', () {
    test('currentUser maps the current Supabase user', () {
      final supabase = _FakeSupabaseAuthGateway(currentUser: _user());
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: _FakeGoogleAuthGateway(),
      );

      final user = repository.currentUser;

      expect(user, isNotNull);
      expect(user!.id, 'user-1');
      expect(user.email, 'listener@example.com');
      expect(user.displayName, 'Pat Listener');
    });

    test('currentUser returns null when signed out', () {
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: _FakeSupabaseAuthGateway(),
        googleAuthGateway: _FakeGoogleAuthGateway(),
      );

      expect(repository.currentUser, isNull);
    });

    test('watchAuthState maps signed-in and signed-out states', () async {
      final supabase = _FakeSupabaseAuthGateway();
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: _FakeGoogleAuthGateway(),
      );

      final values = <String?>[];
      final subscription = repository.watchAuthState().listen(
        (user) => values.add(user?.id),
      );

      supabase.emit(AuthState(AuthChangeEvent.signedIn, _session(_user())));
      supabase.emit(const AuthState(AuthChangeEvent.signedOut, null));

      await Future<void>.delayed(Duration.zero);

      expect(values, <String?>['user-1', null]);

      await subscription.cancel();
      await supabase.dispose();
    });

    test('Google cancellation does not call Supabase sign in', () async {
      final supabase = _FakeSupabaseAuthGateway();
      final google = _FakeGoogleAuthGateway();
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: google,
      );

      final result = await repository.signInWithGoogle();

      expect(result, isNull);
      expect(supabase.signInCallCount, 0);

      await supabase.dispose();
    });

    test('exchanges Google tokens with Supabase and maps user', () async {
      final supabase = _FakeSupabaseAuthGateway(signInUser: _user());
      final google = _FakeGoogleAuthGateway(
        signInResult: const GoogleAuthCredential(
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      );
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: google,
      );

      final result = await repository.signInWithGoogle();

      expect(result, isNotNull);
      expect(result!.id, 'user-1');

      expect(supabase.signInCallCount, 1);
      expect(supabase.lastProvider, OAuthProvider.google);
      expect(supabase.lastIdToken, 'google-id-token');
      expect(supabase.lastAccessToken, 'google-access-token');

      await supabase.dispose();
    });

    test('throws when Supabase sign in returns no user', () async {
      final supabase = _FakeSupabaseAuthGateway();
      final google = _FakeGoogleAuthGateway(
        signInResult: const GoogleAuthCredential(
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      );
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: google,
      );

      await expectLater(
        repository.signInWithGoogle(),
        throwsA(isA<StateError>()),
      );

      await supabase.dispose();
    });

    test('signOut signs out of both Supabase and Google', () async {
      final supabase = _FakeSupabaseAuthGateway();
      final google = _FakeGoogleAuthGateway();
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: google,
      );

      await repository.signOut();

      expect(supabase.signOutCallCount, 1);
      expect(google.signOutCallCount, 1);

      await supabase.dispose();
    });

    test('still signs out Google when Supabase sign out fails', () async {
      final error = StateError('Supabase sign out failed.');
      final supabase = _FakeSupabaseAuthGateway(signOutError: error);
      final google = _FakeGoogleAuthGateway();
      final repository = SupabaseAccountRepository(
        supabaseAuthGateway: supabase,
        googleAuthGateway: google,
      );

      await expectLater(repository.signOut(), throwsA(same(error)));

      expect(supabase.signOutCallCount, 1);
      expect(google.signOutCallCount, 1);

      await supabase.dispose();
    });

    test(
      'propagates Google sign out failure after Supabase succeeds',
      () async {
        final error = StateError('Google sign out failed.');
        final supabase = _FakeSupabaseAuthGateway();
        final google = _FakeGoogleAuthGateway(signOutError: error);
        final repository = SupabaseAccountRepository(
          supabaseAuthGateway: supabase,
          googleAuthGateway: google,
        );

        await expectLater(repository.signOut(), throwsA(same(error)));

        expect(supabase.signOutCallCount, 1);
        expect(google.signOutCallCount, 1);

        await supabase.dispose();
      },
    );
  });
}

User _user() {
  return const User(
    id: 'user-1',
    appMetadata: <String, dynamic>{},
    userMetadata: <String, dynamic>{'full_name': 'Pat Listener'},
    aud: 'authenticated',
    email: 'listener@example.com',
    createdAt: '2026-09-12T00:00:00.000Z',
  );
}

Session _session(User user) {
  return Session(
    accessToken: 'supabase-access-token',
    expiresIn: 3600,
    refreshToken: 'supabase-refresh-token',
    tokenType: 'bearer',
    user: user,
  );
}

class _FakeGoogleAuthGateway implements GoogleAuthGateway {
  _FakeGoogleAuthGateway({this.signInResult, this.signOutError});

  final GoogleAuthCredential? signInResult;
  final Object? signOutError;

  int signOutCallCount = 0;

  @override
  Future<GoogleAuthCredential?> signIn() async {
    return signInResult;
  }

  @override
  Future<void> signOut() async {
    signOutCallCount += 1;

    final error = signOutError;

    if (error != null) {
      throw error;
    }
  }
}

class _FakeSupabaseAuthGateway implements SupabaseAuthGateway {
  _FakeSupabaseAuthGateway({
    this.currentUser,
    this.signInUser,
    this.signOutError,
  });

  @override
  final User? currentUser;

  final User? signInUser;
  final Object? signOutError;

  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  int signInCallCount = 0;
  int signOutCallCount = 0;

  OAuthProvider? lastProvider;
  String? lastIdToken;
  String? lastAccessToken;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  void emit(AuthState state) {
    _controller.add(state);
  }

  Future<void> dispose() {
    return _controller.close();
  }

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    required String accessToken,
  }) async {
    signInCallCount += 1;
    lastProvider = provider;
    lastIdToken = idToken;
    lastAccessToken = accessToken;

    return AuthResponse(user: signInUser);
  }

  @override
  Future<void> signOut() async {
    signOutCallCount += 1;

    final error = signOutError;

    if (error != null) {
      throw error;
    }
  }
}
