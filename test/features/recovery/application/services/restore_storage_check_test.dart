import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/recovery/application/models/restore_preflight.dart';
import 'package:sonus_next/features/recovery/application/services/restore_preflight_service.dart';
import 'package:sonus_next/features/recovery/application/services/storage_space_probe.dart';

import '../../../../support/recovery_fixtures.dart';

bool _android() => true;
bool _notAndroid() => false;

class _FixedProbe implements StorageSpaceProbe {
  const _FixedProbe(this.bytes);

  final int? bytes;

  @override
  Future<int?> availableBytes(String path) async => bytes;
}

class _FailingProbe implements StorageSpaceProbe {
  const _FailingProbe();

  @override
  Future<int?> availableBytes(String path) async =>
      throw const StorageSpaceUnavailable('StatFs failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const channel = MethodChannel(PlatformStorageSpaceProbe.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory root;
  late AppDatabase target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_storage_');
    target = fileAppDatabase(root, 'target.db');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await target.close();

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  group('platform probe', () {
    test('reads StatFs available bytes on Android', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return 123456;
      });

      final bytes = await const PlatformStorageSpaceProbe(
        isAndroid: _android,
      ).availableBytes('/data/app');

      expect(bytes, 123456);
      expect(received!.method, 'availableBytes');
      expect(received!.arguments, {'path': '/data/app'});
    });

    test('a native failure is reported, not treated as unknown', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'STORAGE_QUERY_FAILED');
      });

      await expectLater(
        const PlatformStorageSpaceProbe(isAndroid: _android).availableBytes('/x'),
        throwsA(isA<StorageSpaceUnavailable>()),
      );
    });

    test('a missing native handler on Android fails closed', () async {
      await expectLater(
        const PlatformStorageSpaceProbe(isAndroid: _android).availableBytes('/x'),
        throwsA(isA<StorageSpaceUnavailable>()),
      );
    });

    test('other platforms report unknown free space', () async {
      expect(
        await const PlatformStorageSpaceProbe(
          isAndroid: _notAndroid,
        ).availableBytes('/x'),
        isNull,
      );
    });
  });

  group('preflight', () {
    Future<RestorePreflight> assess(StorageSpaceProbe? probe) async {
      await seedConnectedLibrary(await target.database, key: 'local');

      final contents = await verifiedFixtureContents(
        directory: root,
        seed: (db) => seedConnectedLibrary(db, key: 'a'),
      );

      return RestorePreflightService(
        appDatabase: target,
        storageProbe: probe,
        storagePath: root.path,
      ).assess(contents);
    }

    test('blocks when free space is below the requirement', () async {
      final result = await assess(const _FixedProbe(1024));

      expect(result.blockers, [RestoreBlocker.insufficientStorage]);
      expect(result.availableBytes, 1024);
      expect(result.isStorageVerified, isTrue);
    });

    test('allows a restore with enough verified space', () async {
      final result = await assess(const _FixedProbe(1 << 40));

      expect(result.blockers, isEmpty);
      expect(result.isStorageVerified, isTrue);
    });

    test('blocks when the platform query fails', () async {
      final result = await assess(const _FailingProbe());

      expect(result.blockers, [RestoreBlocker.storageCheckFailed]);
      expect(result.isStorageVerified, isFalse);
    });

    test('reports unverified space where the platform cannot tell', () async {
      final result = await assess(const _FixedProbe(null));

      expect(result.blockers, isEmpty);
      expect(result.isStorageVerified, isFalse);
    });

    test('the estimate includes the safety backup of local data', () async {
      final withLocal = await assess(null);

      final emptyTarget = fileAppDatabase(root, 'empty.db');
      addTearDown(emptyTarget.close);

      final contents = await verifiedFixtureContents(
        directory: root,
        backupId: 'second',
        seed: (db) => seedConnectedLibrary(db, key: 'a'),
      );

      final withoutLocal = await RestorePreflightService(
        appDatabase: emptyTarget,
      ).assess(contents);

      expect(
        withLocal.estimatedRequiredBytes,
        greaterThan(withoutLocal.estimatedRequiredBytes),
      );
    });
  });
}
