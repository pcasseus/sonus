import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/models/sync_failure.dart';
import '../../application/services/outbound_sync_processor.dart';

/// Classifies sync errors raised by the Supabase clients.
SyncFailureKind classifySupabaseSyncFailure(Object error) {
  return switch (error) {
    OutboundRecordWriteConflict() => SyncFailureKind.conflict,
    // Network failures during auth, including timeouts, arrive wrapped.
    AuthRetryableFetchException() => SyncFailureKind.offline,
    AuthException() => SyncFailureKind.signIn,
    PostgrestException(:final code) => _fromStatus(code),
    StorageException(:final statusCode) => _fromStatus(statusCode),
    _ => classifySyncFailure(error),
  };
}

/// The server's error code when there is one, otherwise the error's type.
String describeSupabaseSyncFailure(Object error) => switch (error) {
  PostgrestException(:final code?) => code,
  StorageException(:final statusCode?) => 'storage $statusCode',
  AuthException(:final statusCode?) => 'auth $statusCode',
  _ => describeSyncFailure(error),
};

SyncFailureKind _fromStatus(String? code) {
  if (code == null) return SyncFailureKind.unknown;
  if (const {'401', '403', 'PGRST301', 'PGRST302'}.contains(code)) {
    return SyncFailureKind.signIn;
  }
  final status = int.tryParse(code);
  if (status != null && status >= 500 && status < 600) {
    return SyncFailureKind.server;
  }
  return SyncFailureKind.unknown;
}
