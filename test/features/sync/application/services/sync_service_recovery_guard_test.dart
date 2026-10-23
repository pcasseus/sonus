import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

class _RejectingGuard implements SyncRunGuard {
  const _RejectingGuard(this.reason);

  final SyncHoldReason reason;

  @override
  Future<T> guard<T>(Future<T> Function() run) async =>
      throw SyncHeldForRecovery(reason);
}

class _PassingGuard implements SyncRunGuard {
  int runs = 0;

  @override
  Future<T> guard<T>(Future<T> Function() run) {
    runs++;
    return run();
  }
}

void main() {
  late List<String> calls;

  SyncService service({SyncRunGuard? guard}) => SyncService.forTesting(
    bindToUser: (_) async => calls.add('bind'),
    claimUnowned: (_) async {
      calls.add('claim');
      return 0;
    },
    getPending: (_) async {
      calls.add('pending');
      return const [];
    },
    pushPending: (_) async => calls.add('push'),
    pullAll: (_) async {
      calls.add('pull');
      return 0;
    },
    runGuard: guard,
  );

  setUp(() => calls = []);

  test('a held run performs no attachment, push, or pull work', () async {
    await expectLater(
      service(
        guard: const _RejectingGuard(SyncHoldReason.assessmentRequired),
      ).synchronize('user-1'),
      throwsA(isA<SyncHeldForRecovery>()),
    );

    expect(calls, isEmpty);
  });

  test('a passing guard wraps the whole run', () async {
    final guard = _PassingGuard();

    await service(guard: guard).synchronize('user-1');

    expect(guard.runs, 1);
    expect(calls, ['bind', 'claim', 'pending', 'push', 'pull', 'pending']);
  });

  test('without a guard synchronization is unchanged', () async {
    await service().synchronize('user-1');

    expect(calls, ['bind', 'claim', 'pending', 'push', 'pull', 'pending']);
  });

  test('controller reports a recovery hold without scheduling a retry', () async {
    final controller = SyncController.forTesting(
      synchronize: service(
        guard: const _RejectingGuard(SyncHoldReason.restoreInProgress),
      ).synchronize,
    );
    addTearDown(controller.dispose);

    final synced = await controller.synchronize('user-1');

    expect(synced, isFalse);
    expect(controller.status, SyncStatus.recoveryHold);
    expect(controller.isRecoveryHeld, isTrue);
    expect(controller.hasError, isFalse);
    expect(controller.retryPending, isFalse);
    expect(controller.recoveryHoldReason, SyncHoldReason.restoreInProgress);
    expect(controller.lastSuccessfulSync, isNull);
    expect(calls, isEmpty);
  });
}
