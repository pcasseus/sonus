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
    final gate = RecoverySyncGate(holdStore: store);
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

    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The hold is durable before the restore proceeds...
    expect(await store.read(), isA<ActiveRecoverySyncHold>());
    // ...new runs are refused synchronously...
    await expectLater(
      gate.guard(() async => events.add('late sync')),
      heldFor(SyncHoldReason.restoreInProgress),
    );
    // ...and the restore has not proceeded while sync is active.
    expect(events, ['sync started']);

    release.complete();
    await activeSync;
    await restore;

    expect(events, ['sync started', 'sync finished', 'restore owns gate']);
    gate.endRestore();
  });

  test('a requested sync that has not begun work is rejected, not run', () async {
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
  });

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

  test('hold round-trips through JSON', () async {
    await store.write(hold());
    final state = await store.read() as ActiveRecoverySyncHold;

    expect(state.hold.toJson(), hold().toJson());
  });
}
