import 'dart:async';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/account_failure.dart';

/// Sorts a sign-in error from Google or Supabase into what the person can
/// do about it. Cancellation never reaches here: it is not a failure.
AccountFailureKind classifyAccountFailure(Object error) => switch (error) {
  SocketException() ||
  TimeoutException() ||
  AuthRetryableFetchException() => AccountFailureKind.offline,
  GoogleSignInException(
    code: GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError,
  ) =>
    AccountFailureKind.googleSetup,
  // Android Credential Manager reports an app whose package and signing
  // key are not registered for Google sign-in as "no credential".
  GoogleSignInException(
    code: GoogleSignInExceptionCode.unknownError,
    :final description?,
  )
      when description.startsWith('No credential available') =>
    AccountFailureKind.googleSetup,
  GoogleSignInException(
    code: GoogleSignInExceptionCode.interrupted ||
        GoogleSignInExceptionCode.uiUnavailable,
  ) =>
    AccountFailureKind.interrupted,
  AuthException() => AccountFailureKind.serverRejected,
  _ => AccountFailureKind.unknown,
};
