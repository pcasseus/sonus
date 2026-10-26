import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/services/cloud_library_first_link_guard.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';

class _Probe implements CloudLibraryProbe {
  _Probe(this.hasRecords);

  final bool hasRecords;
  int calls = 0;

  @override
  Future<bool> hasLibrary(String userId) async {
    calls++;
    return hasRecords;
  }
}

class _Consent implements CloudLibraryConsentStore {
  final granted = <String>{};

  @override
  Future<bool> hasConsent(String userId) async => granted.contains(userId);

  @override
  Future<void> grant(String userId) async => granted.add(userId);
}

void main() {
  group('the first-link guard', () {
    Future<Object?> check({
      String? boundUserId,
      bool cloudHasLibrary = true,
      _Consent? consent,
    }) async {
      try {
        await CloudLibraryFirstLinkGuard(
          boundUserId: () async => boundUserId,
          probe: _Probe(cloudHasLibrary),
          consent: consent ?? _Consent(),
        ).check('user-1');
        return null;
      } catch (error) {
        return error;
      }
    }

    test('stops a new device before an existing cloud library', () async {
      expect(await check(), isA<SyncNeedsCloudLibraryChoice>());
    });

    test('lets a new device link to an empty account', () async {
      expect(await check(cloudHasLibrary: false), isNull);
    });

    test('never stops a device already linked', () async {
      final probe = _Probe(true);
      await CloudLibraryFirstLinkGuard(
        boundUserId: () async => 'user-1',
        probe: probe,
        consent: _Consent(),
      ).check('user-1');

      expect(probe.calls, 0, reason: 'no extra cloud reads for linked devices');
    });

    test('lets the person bring the library once they choose to', () async {
      final consent = _Consent()..granted.add('user-1');

      expect(await check(consent: consent), isNull);
    });

    test('a choice for one account is not a choice for another', () async {
      final consent = _Consent()..granted.add('user-2');

      expect(await check(consent: consent), isA<SyncNeedsCloudLibraryChoice>());
    });
  });

  group('the sync run', () {
    SyncService service(
      List<String> calls, {
      Future<void> Function(String userId)? guard,
      Future<void> Function(String userId)? archive,
      Future<void> Function(String userId)? push,
    }) => SyncService.forTesting(
      bindToUser: (_) async => calls.add('bind'),
      claimUnowned: (_) async {
        calls.add('claim');
        return 0;
      },
      attachAccount: (_) async {
        calls.add('attach');
        return 0;
      },
      getPending: (_) async => const [],
      pushPending: push ?? (_) async => calls.add('push'),
      pullAll: (_) async {
        calls.add('pull');
        return 0;
      },
      firstLinkGuard: guard,
      syncArchive: archive,
      now: () => DateTime.utc(2026, 10, 25),
    );

    test('a stopped first link binds, claims and moves nothing', () async {
      final calls = <String>[];

      await expectLater(
        service(
          calls,
          guard: (_) async => throw const SyncNeedsCloudLibraryChoice(),
          archive: (_) async => calls.add('archive'),
        ).synchronize('user-1'),
        throwsA(isA<SyncNeedsCloudLibraryChoice>()),
      );

      expect(calls, isEmpty);
    });

    test('the archive follows the library', () async {
      final calls = <String>[];

      await service(
        calls,
        guard: (_) async => calls.add('guard'),
        archive: (_) async => calls.add('archive'),
      ).synchronize('user-1');

      expect(calls, ['guard', 'attach', 'push', 'pull', 'archive']);
    });

    test('an archive failure fails the run', () async {
      await expectLater(
        service(
          [],
          archive: (_) async => throw StateError('archive down'),
        ).synchronize('user-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('the sync controller', () {
    test('waits for the choice, then brings the library', () async {
      final consent = _Consent();
      final runs = <String>[];
      final controller = SyncController.forTesting(
        synchronize: (userId) async {
          runs.add(userId);
          if (!await consent.hasConsent(userId)) {
            throw const SyncNeedsCloudLibraryChoice();
          }
          return SyncRunResult(
            userId: userId,
            startedAt: DateTime.utc(2026, 10, 25),
            completedAt: DateTime.utc(2026, 10, 25, 0, 0, 1),
            claimedUnownedCount: 0,
            pendingBeforePush: 0,
            pulledRecordCount: 4,
            pendingAfterSync: 0,
          );
        },
        grantCloudLibrary: consent.grant,
      );
      addTearDown(controller.dispose);

      expect(await controller.synchronize('user-1'), isFalse);
      expect(controller.status, SyncStatus.awaitingCloudChoice);
      expect(controller.isAwaitingCloudChoice, isTrue);
      expect(controller.hasError, isFalse, reason: 'not a failure');

      expect(await controller.bringCloudLibrary(), isTrue);
      expect(consent.granted, {'user-1'});
      expect(controller.isAwaitingCloudChoice, isFalse);
      expect(runs, ['user-1', 'user-1']);
    });

    test('without a signed-in account nothing is granted', () async {
      final consent = _Consent();
      final controller = SyncController.forTesting(
        synchronize: (_) async => throw StateError('not reached'),
        grantCloudLibrary: consent.grant,
      );
      addTearDown(controller.dispose);

      expect(await controller.bringCloudLibrary(), isFalse);
      expect(consent.granted, isEmpty);
    });
  });
}
