import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';

void main() {
  group('CloudConditionalWriteResult', () {
    test('parses a verified replay outcome', () {
      final result = CloudConditionalWriteResult.fromRpcRow({
        'outcome': 'replayed',
        'server_revision': 8,
      });

      expect(result.outcome, CloudConditionalWriteOutcome.replayed);
      expect(result.serverRevision, 8);
    });

    test('parses an applied outcome', () {
      final result = CloudConditionalWriteResult.fromRpcRow({
        'outcome': 'applied',
        'server_revision': 8,
      });

      expect(result.outcome, CloudConditionalWriteOutcome.applied);
      expect(result.serverRevision, 8);
    });

    test('rejects replay without a server revision', () {
      expect(
        () => CloudConditionalWriteResult.fromRpcRow({
          'outcome': 'replayed',
          'server_revision': null,
        }),
        throwsStateError,
      );
    });

    test('rejects replay with revision zero', () {
      expect(
        () => CloudConditionalWriteResult.fromRpcRow({
          'outcome': 'replayed',
          'server_revision': 0,
        }),
        throwsStateError,
      );
    });

    test('preserves conflict revision', () {
      final result = CloudConditionalWriteResult.fromRpcRow({
        'outcome': 'conflict',
        'server_revision': 9,
      });

      expect(result.outcome, CloudConditionalWriteOutcome.conflict);
      expect(result.serverRevision, 9);
    });

    test('not found cannot include a revision', () {
      expect(
        () => CloudConditionalWriteResult.fromRpcRow({
          'outcome': 'not_found',
          'server_revision': 9,
        }),
        throwsStateError,
      );
    });

    test('rejects unknown outcomes', () {
      expect(
        () => CloudConditionalWriteResult.fromRpcRow({
          'outcome': 'unexpected',
          'server_revision': 8,
        }),
        throwsStateError,
      );
    });
  });
}
