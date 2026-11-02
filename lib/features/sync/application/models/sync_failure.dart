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

  /// The cloud does not support this version of Sonus yet (its schema or
  /// sync functions are missing or answer differently). Retrying on its own
  /// cannot help, so sync pauses until the person retries (SN-50).
  cloudNotReady(
    "The Sonus cloud doesn't support this version of Sonus yet, so sync is "
    'paused. Your changes stay on this device. Try again after the cloud is '
    'updated.',
  ),
  unknown('Sync could not finish. Your changes are kept.');

  const SyncFailureKind(this.message);

  final String message;

  /// Whether retrying automatically cannot help. Decided by what the error
  /// is, never by how often it happened.
  bool get isPermanent => this == SyncFailureKind.cloudNotReady;
}

/// The cloud answered a sync request in a shape this version of Sonus
/// does not understand, such as a conditional write without a valid
/// server revision: its sync functions are missing or older.
class CloudContractMismatch extends StateError {
  CloudContractMismatch(super.message);
}

typedef SyncFailureClassifier = SyncFailureKind Function(Object error);

/// A short, non-sensitive code for a failure, such as a server error code
/// ("42501") or the error's type, shown so a failure can be diagnosed.
/// Never a message: messages can contain names or record contents.
typedef SyncFailureDescriber = String Function(Object error);

String describeSyncFailure(Object error) => '${error.runtimeType}';

/// Classifies errors that need no cloud SDK to recognise.
SyncFailureKind classifySyncFailure(Object error) => switch (error) {
  CloudContractMismatch() => SyncFailureKind.cloudNotReady,
  TimeoutException() => SyncFailureKind.timeout,
  SocketException() || http.ClientException() => SyncFailureKind.offline,
  _ => SyncFailureKind.unknown,
};
