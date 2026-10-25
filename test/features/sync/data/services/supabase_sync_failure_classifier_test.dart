import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sonus_next/core/network/timed_http_client.dart';
import 'package:sonus_next/features/sync/application/models/sync_failure.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_sync_processor.dart';
import 'package:sonus_next/features/sync/data/services/supabase_sync_failure_classifier.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  final cases = <String, (Object, SyncFailureKind)>{
    'request timeout': (
      NetworkTimeoutException(
        NetworkTimeoutPhase.response,
        const Duration(seconds: 45),
        null,
      ),
      SyncFailureKind.timeout,
    ),
    'plain timeout': (TimeoutException('x'), SyncFailureKind.timeout),
    'no network': (
      const SocketException('unreachable'),
      SyncFailureKind.offline,
    ),
    'token refresh could not reach the server': (
      AuthRetryableFetchException(message: 'No response within 45s'),
      SyncFailureKind.offline,
    ),
    'session rejected': (
      const AuthException('refresh_token_not_found'),
      SyncFailureKind.signIn,
    ),
    'expired token on a table read': (
      const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
      SyncFailureKind.signIn,
    ),
    'forbidden': (
      const PostgrestException(message: 'denied', code: '403'),
      SyncFailureKind.signIn,
    ),
    'server error': (
      const PostgrestException(message: 'down', code: '503'),
      SyncFailureKind.server,
    ),
    'storage server error': (
      const StorageException('down', statusCode: '500'),
      SyncFailureKind.server,
    ),
    'write conflict': (
      const OutboundRecordWriteConflict(
        entityType: CloudDataEntity.album,
        entityId: 'album_1',
        outcome: CloudConditionalWriteOutcome.conflict,
        expectedServerRevision: 1,
        observedServerRevision: 3,
      ),
      SyncFailureKind.conflict,
    ),
    'anything else': (StateError('x'), SyncFailureKind.unknown),
  };

  for (final MapEntry(key: name, value: (error, kind)) in cases.entries) {
    test(name, () => expect(classifySupabaseSyncFailure(error), kind));
  }

  test(
    'every failure tells the person their changes are safe or what to do',
    () {
      for (final kind in SyncFailureKind.values) {
        expect(kind.message, isNotEmpty);
      }
    },
  );
}
