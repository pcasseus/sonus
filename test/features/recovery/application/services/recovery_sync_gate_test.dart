import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/models/recovery_sync_hold.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_gate.dart';
import 'package:sonus_next/features/recovery/application/services/recovery_sync_hold_store.dart';
import 'package:sonus_next/features/sync/application/services/sync_run_guard.dart';

void main() {
  late Directory root;
  late RecoverySyncHoldStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_gate_');
    store = RecoverySyncHoldStore(directory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  RecoverySyncHold hold({
    RecoverySyncHoldPhase phase = RecoverySyncHoldPhase.restoring,
  }) => RecoverySyncHold(
    holdId: 'hold-1',
    backupId: 'backup-1',
    createdAtUtc: DateTime.utc(2026, 10, 21),
    phase: phase,
    backupAccountIds: const {'user-1'},
    preRestore: RecoveryFingerprint(
      tableDigests: const {'artists': 'abc'},
      artworkContentDigest: 'def',
    ),
  );

  Matcher heldFor(SyncHoldReason reason) => throwsA(
    isA<SyncHeldForRecovery>().having((e) => e.reason, 'reason', reason),
  );

  test('runs sync normally when no hold exists', () async {
    final gate = RecoverySyncGate(holdStore: store);

    expect(await gate.guard(() async => 42), 42);
    expect(gate.activeSyncRuns, 0);
  });

  test('a persisted hold survives an app restart', () async {
    await store.write(hold(phase: RecoverySyncHoldPhase.assessmentRequired));

    // A brand-new gate models a fresh process after restart.
    final restarted = RecoverySyncGate(
      holdStore: RecoverySyncHoldStore(directory: () async => root),
    );
    var ran = false;

    await expectLater(
      restarted.guard(() async => ran = true),
      heldFor(SyncHoldReason.assessmentRequired),
    );
    expect(ran, isFalse);
  });

  test('an interrupted restore keeps sync paused after restart', () async {
    await store.write(hold());

    await expectLater(
      RecoverySyncGate(holdStore: store).guard(() async {}),
      heldFor(SyncHoldReason.restoreInProgress),
    );
  });

  test('an unreadable hold fails closed', () async {
    await File(
      path.join(root.path, RecoverySyncHoldStore.fileName),
    ).writeAsString('{not json');

    await expectLater(
      RecoverySyncGate(holdStore: store).guard(() async {}),
      heldFor(SyncHoldReason.holdStateUnreadable),
    );

    expect(await store.read(), isA<UnreadableRecoverySyncHold>());
  });

  test('restore waits for an active sync and blocks new ones', () async {
    final observed = _ObservedHoldStore(directory: () async => root);
    final gate = RecoverySyncGate(holdStore: observed);
    final started = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];

    final activeSync = gate.guard(() async {
      events.add('sync started');
      started.complete();
      await release.future;
      events.add('sync finished');
    });

    // The run is inside its work (push/pull) before the restore begins.
    await started.future;
    expect(gate.activeSyncRuns, 1);

    final restore = gate.beginRestore((_) => hold()).then((_) {
      events.add('restore owns gate');
    });

    try {
      // Wait for the restore's hold write itself to finish: its temporary
      // has been renamed over the hold file. The timeout only turns a hang
      // into a failure; it is not what the test waits for.
      await observed.firstWriteCompleted.timeout(const Duration(seconds: 30));

      // The hold is durable before the restore proceeds...
      expect(await store.read(), isA<ActiveRecoverySyncHold>());
      // ...new runs are refused synchronously...
      await expectLater(
        gate.guard(() async => events.add('late sync')),
        heldFor(SyncHoldReason.restoreInProgress),
      );
      // ...and the restore has not proceeded while sync is active.
      expect(events, ['sync started']);
    } finally {
      // Even after a failure, let the sync and the restore (and its hold
      // write) finish before tearDown removes their directory.
      if (!release.isCompleted) release.complete();
      await activeSync;

      try {
        await restore;
      } finally {
        gate.endRestore();
      }
    }

    expect(events, ['sync started', 'sync finished', 'restore owns gate']);
  });

  test('new runs are refused before the hold write has completed', () async {
    final observed = _ObservedHoldStore(directory: () async => root)
      ..writeGate = Completer<void>();
    final gate = RecoverySyncGate(holdStore: observed);

    final restore = gate.beginRestore((_) => hold());

    try {
      // Admission closes synchronously, before anything is durable: however
      // long the write takes, elapsed time alone proves nothing about it.
      await expectLater(
        gate.guard(() async {}),
        heldFor(SyncHoldReason.restoreInProgress),
      );
      expect(await store.read(), isA<NoRecoverySyncHold>());
    } finally {
      observed.writeGate!.complete();
      try {
        await restore;
      } finally {
        gate.endRestore();
      }
    }

    expect(await store.read(), isA<ActiveRecoverySyncHold>());
  });

  test(
    'a requested sync that has not begun work is rejected, not run',
    () async {
      final gate = RecoverySyncGate(holdStore: store);
      var ran = false;

      // Requested, but still checking the persisted hold.
      final pending = expectLater(
        gate.guard(() async => ran = true),
        throwsA(
          isA<SyncHeldForRecovery>().having(
            (e) => e.reason,
            'reason',
            SyncHoldReason.restoreInProgress,
          ),
        ),
      );

      await gate.beginRestore((_) => hold());
      await pending;
      expect(ran, isFalse);
      expect(gate.activeSyncRuns, 0);

      gate.endRestore();
    },
  );

  test('a sync that never finishes aborts the restore safely', () async {
    final gate = RecoverySyncGate(
      holdStore: store,
      drainTimeout: const Duration(milliseconds: 50),
    );
    final started = Completer<void>();
    final release = Completer<void>();
    final activeSync = gate.guard(() {
      started.complete();
      return release.future;
    });
    await started.future;

    await expectLater(
      gate.beginRestore((_) => hold()),
      throwsA(isA<RecoveryGateUnavailable>()),
    );

    // The previous (absent) hold is reinstated and the gate is free.
    expect(await store.read(), isA<NoRecoverySyncHold>());
    expect(gate.isRestoreActive, isFalse);

    release.complete();
    await activeSync;
  });

  test('a failed hold write reinstates the previous hold', () async {
    final previous = hold(phase: RecoverySyncHoldPhase.assessmentRequired);
    await store.write(previous);
    final gate = RecoverySyncGate(holdStore: store);

    await expectLater(
      gate.beginRestore((_) => throw StateError('cannot build hold')),
      throwsStateError,
    );

    final state = await store.read();
    expect(state, isA<ActiveRecoverySyncHold>());
    expect(
      (state as ActiveRecoverySyncHold).hold.phase,
      RecoverySyncHoldPhase.assessmentRequired,
    );
    expect(gate.isRestoreActive, isFalse);
  });

  test('only one restore may own the gate', () async {
    final gate = RecoverySyncGate(holdStore: store);
    await gate.beginRestore((_) => hold());

    await expectLater(
      gate.beginRestore((_) => hold()),
      throwsA(isA<RecoveryGateUnavailable>()),
    );

    gate.endRestore();
  });

  test('ending a restore leaves the persisted hold in force', () async {
    final gate = RecoverySyncGate(holdStore: store);
    await gate.beginRestore((_) => hold());
    gate.endRestore();

    await expectLater(
      gate.guard(() async {}),
      heldFor(SyncHoldReason.restoreInProgress),
    );

    await store.clear();
    expect(await gate.guard(() async => 'ok'), 'ok');
  });

  group('startup check', () {
    test('sync is rejected until the startup check passes', () async {
      final gate = RecoverySyncGate(
        holdStore: store,
        requiresStartupCheck: true,
      );
      var ran = false;

      await expectLater(
        gate.guard(() async => ran = true),
        heldFor(SyncHoldReason.recoveryCheckPending),
      );

      await gate.runStartupCheck(() async {});

      expect(gate.isStartupCheckComplete, isTrue);
      await gate.guard(() async => ran = true);
      expect(ran, isTrue);
    });

    test('a failed startup check keeps sync blocked until retried', () async {
      final gate = RecoverySyncGate(
        holdStore: store,
        requiresStartupCheck: true,
      );

      await expectLater(
        gate.runStartupCheck(() async => throw StateError('io')),
        throwsStateError,
      );

      expect(gate.hasStartupCheckFailed, isTrue);
      await expectLater(
        gate.guard(() async {}),
        heldFor(SyncHoldReason.recoveryCheckFailed),
      );

      await gate.runStartupCheck(() async {});
      expect(await gate.guard(() async => 'ok'), 'ok');
    });

    test('a passed check does not lift a persisted hold', () async {
      await store.write(hold(phase: RecoverySyncHoldPhase.assessmentRequired));
      final gate = RecoverySyncGate(
        holdStore: store,
        requiresStartupCheck: true,
      );

      await gate.runStartupCheck(() async {});

      await expectLater(
        gate.guard(() async {}),
        heldFor(SyncHoldReason.assessmentRequired),
      );
    });

    test('the application gate requires the startup check', () {
      expect(RecoverySyncGate.application.requiresStartupCheck, isTrue);
    });
  });

  test('hold round-trips through JSON', () async {
    await store.write(hold());
    final state = await store.read() as ActiveRecoverySyncHold;

    expect(state.hold.toJson(), hold().toJson());
  });
}

/// A real hold store that reports when a write has fully completed (the
/// atomic rename included), and can hold a write back until released.
class _ObservedHoldStore extends RecoverySyncHoldStore {
  _ObservedHoldStore({required super.directory});

  final _firstWrite = Completer<void>();

  /// When set, writes wait for it before touching the file system.
  Completer<void>? writeGate;

  Future<void> get firstWriteCompleted => _firstWrite.future;

  @override
  Future<void> write(RecoverySyncHold hold) async {
    await writeGate?.future;
    await super.write(hold);

    if (!_firstWrite.isCompleted) _firstWrite.complete();
  }
}
