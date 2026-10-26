import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why a sync attempt failed, in terms a person can act on.
enum SyncFailureKind {
  timeout(
    'The Sonus cloud did not respond in time. Your changes are kept and '
    'will sync on the next try.',
  ),
  offline(
    'Sonus could not reach the cloud. Check your connection; your changes '
    'are kept.',
  ),
  signIn('Your sign-in needs refreshing. Sign in again to keep syncing.'),
  server(
    'The Sonus cloud had a problem. Your changes are kept; try again '
    'shortly.',
  ),
  conflict('Some changes differ from the cloud and need review.'),
  unknown('Sync could not finish. Your changes are kept.');

  const SyncFailureKind(this.message);

  final String message;
}

typedef SyncFailureClassifier = SyncFailureKind Function(Object error);

/// Classifies errors that need no cloud SDK to recognise.
SyncFailureKind classifySyncFailure(Object error) => switch (error) {
  TimeoutException() => SyncFailureKind.timeout,
  SocketException() || http.ClientException() => SyncFailureKind.offline,
  _ => SyncFailureKind.unknown,
};
