import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sonus_next/core/network/timed_http_client.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
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

  test('SN-49: a failure is described by its code, never its message', () {
    expect(
      describeSupabaseSyncFailure(
        const PostgrestException(
          message: 'permission denied for table songs',
          code: '42501',
        ),
      ),
      '42501',
    );
    expect(
      describeSupabaseSyncFailure(
        const AuthException(
          'JWT expired for someone@example.com',
          statusCode: '401',
        ),
      ),
      'auth 401',
    );
    expect(describeSupabaseSyncFailure(StateError('secret')), 'StateError');
  });

  test('SN-49: the device log names the failure, never server text', () {
    expect(
      SyncController.syncFailureLogLine(
        SyncFailureKind.unknown,
        'StateError',
        StateError('Cloud returned more than one row for song-1.'),
      ),
      'sonus.sync: sync failed (unknown, StateError): '
      'Cloud returned more than one row for song-1.',
    );
    final server = SyncController.syncFailureLogLine(
      SyncFailureKind.unknown,
      '42501',
      const PostgrestException(
        message: 'permission denied for someone@example.com',
        code: '42501',
      ),
    );
    expect(server, 'sonus.sync: sync failed (unknown, 42501)');
  });

  group('SN-50: a cloud that is not ready for this version', () {
    test('missing tables, columns and functions are permanent', () {
      for (final code in [
        '42P01',
        '42883',
        '42703',
        'PGRST202',
        'PGRST204',
        'PGRST205',
      ]) {
        final kind = classifySupabaseSyncFailure(
          PostgrestException(message: 'missing', code: code),
        );
        expect(kind, SyncFailureKind.cloudNotReady, reason: code);
        expect(kind.isPermanent, isTrue, reason: code);
      }
    });

    test('a conditional write without a valid revision is permanent', () {
      final error = _thrownBy(
        () => CloudConditionalWriteResult.fromRpcRow({
          'outcome': 'applied',
          'server_revision': null,
        }),
      );

      expect(error, isA<CloudContractMismatch>());
      expect(error, isA<StateError>(), reason: 'still a StateError');
      expect(
        classifySupabaseSyncFailure(error!),
        SyncFailureKind.cloudNotReady,
      );
    });

    test('timeouts, offline, sign-in and server errors stay temporary', () {
      for (final error in <Object>[
        TimeoutException('x'),
        const SocketException('unreachable'),
        const AuthException('expired'),
        const PostgrestException(message: 'busy', code: '503'),
        StateError('anything else'),
      ]) {
        expect(
          classifySupabaseSyncFailure(error).isPermanent,
          isFalse,
          reason: '$error',
        );
      }
    });
  });
}

Object? _thrownBy(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  return null;
}
