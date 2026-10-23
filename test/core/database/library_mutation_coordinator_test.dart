import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';

void main() {
  test('ordinary mutations run successfully', () async {
    final coordinator = LibraryMutationCoordinator();

    final result = await coordinator.runMutation(() async => 42);

    expect(result, 42);
    expect(coordinator.activeMutations, 0);
  });

  test('restore waits for active mutations to finish', () async {
    final coordinator = LibraryMutationCoordinator();
    final releaseMutation = Completer<void>();
    final enteredMutation = Completer<void>();

    final mutation = coordinator.runMutation(() async {
      enteredMutation.complete();
      await releaseMutation.future;
    });

    await enteredMutation.future;

    var restoreStarted = false;

    final restore = coordinator.runExclusiveRestore(() async {
      restoreStarted = true;
    });

    expect(coordinator.isRestoreRequested, isTrue);
    expect(restoreStarted, isFalse);

    await expectLater(
      coordinator.runMutation(() async {}),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    releaseMutation.complete();

    await mutation;
    await restore;

    expect(restoreStarted, isTrue);
    expect(coordinator.isRestoreRequested, isFalse);
  });

  test('restore failure releases mutation admission', () async {
    final coordinator = LibraryMutationCoordinator();

    await expectLater(
      coordinator.runExclusiveRestore<void>(() async {
        throw StateError('Injected restore failure');
      }),
      throwsStateError,
    );

    expect(coordinator.isRestoreRequested, isFalse);

    await coordinator.runMutation(() async {});
  });

  test('simultaneous restore requests cannot both enter', () async {
    final coordinator = LibraryMutationCoordinator();
    final releaseRestore = Completer<void>();

    final first = coordinator.runExclusiveRestore(() async {
      await releaseRestore.future;
    });

    await expectLater(
      coordinator.runExclusiveRestore(() async {}),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    releaseRestore.complete();
    await first;

    expect(coordinator.isRestoreRequested, isFalse);
  });

  test('restore timeout releases admission safely', () async {
    final coordinator = LibraryMutationCoordinator(drainTimeout: Duration.zero);

    final releaseMutation = Completer<void>();

    final mutation = coordinator.runMutation(() async {
      await releaseMutation.future;
    });

    await expectLater(
      coordinator.runExclusiveRestore(() async {}),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    expect(coordinator.isRestoreRequested, isFalse);

    releaseMutation.complete();
    await mutation;

    await coordinator.runMutation(() async {});
  });

  test('mutation cannot enter while exclusive restore runs', () async {
    final coordinator = LibraryMutationCoordinator();

    await coordinator.runExclusiveRestore(() async {
      expect(coordinator.isRestoreRequested, isTrue);

      await expectLater(
        coordinator.runMutation(() async {}),
        throwsA(isA<LibraryMutationUnavailable>()),
      );
    });
  });

  test('mutation failure releases active registration', () async {
    final coordinator = LibraryMutationCoordinator();

    await expectLater(
      coordinator.runMutation<void>(() async {
        throw StateError('Injected mutation failure');
      }),
      throwsStateError,
    );

    expect(coordinator.activeMutations, 0);

    final result = await coordinator.runExclusiveRestore(() async => 42);

    expect(result, 42);
    expect(coordinator.isRestoreRequested, isFalse);
  });

  test('restore can retry after a timed-out mutation finishes', () async {
    final coordinator = LibraryMutationCoordinator(drainTimeout: Duration.zero);

    final releaseMutation = Completer<void>();

    final mutation = coordinator.runMutation(() async {
      await releaseMutation.future;
      return 'mutation completed';
    });

    await expectLater(
      coordinator.runExclusiveRestore(() async => 'first restore'),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    expect(coordinator.isRestoreRequested, isFalse);
    expect(coordinator.activeMutations, 1);

    releaseMutation.complete();

    expect(await mutation, 'mutation completed');
    expect(coordinator.activeMutations, 0);

    final result = await coordinator.runExclusiveRestore(
      () async => 'second restore',
    );

    expect(result, 'second restore');
    expect(coordinator.isRestoreRequested, isFalse);
  });

  test('nested mutation is rejected during exclusive restore', () async {
    final coordinator = LibraryMutationCoordinator();

    var nestedActionExecuted = false;

    await coordinator.runExclusiveRestore(() async {
      await expectLater(
        coordinator.runMutation(() async {
          nestedActionExecuted = true;
        }),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect(coordinator.activeMutations, 0);
    });

    expect(nestedActionExecuted, isFalse);
  });
}
