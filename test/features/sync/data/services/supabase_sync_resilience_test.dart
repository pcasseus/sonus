import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sonus_next/core/network/timed_http_client.dart';
import 'package:sonus_next/features/sync/application/controllers/sync_controller.dart';
import 'package:sonus_next/features/sync/application/models/sync_failure.dart';
import 'package:sonus_next/features/sync/application/services/sync_service.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/data/services/supabase_sync_failure_classifier.dart';
import 'package:sonus_next/features/sync/data/services/sync_status_store.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

/// The real Supabase client and Sonus gateway against a local server on
/// the loopback interface. No real cloud, account or data is involved.
void main() {
  late HttpServer server;
  late SupabaseClient client;
  late void Function(HttpRequest request) respond;
  final held = <HttpRequest>[];
  final saved = <String>[];

  setUp(() async {
    held.clear();
    saved.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request));
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      httpClient: TimedHttpClient(
        connectTimeout: const Duration(milliseconds: 100),
        responseTimeout: const Duration(milliseconds: 150),
        transferIdleTimeout: const Duration(milliseconds: 150),
      ),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    for (final request in held) {
      await request.response.close();
    }
    await client.dispose();
    await server.close(force: true);
  });

  void reply(int status, Object body) {
    respond = (request) {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      unawaited(request.response.close());
    };
  }

  Future<SyncRunResult> readOneAlbum(String userId) async {
    await SupabaseCloudSyncGateway(client: client).fetchCurrent(
      userId: userId,
      entityType: CloudDataEntity.album,
      entityId: 'album_1',
    );
    final now = DateTime.utc(2026, 10, 25);
    return SyncRunResult(
      userId: userId,
      startedAt: now,
      completedAt: now,
      claimedUnownedCount: 0,
      pendingBeforePush: 0,
      pulledRecordCount: 1,
      pendingAfterSync: 0,
    );
  }

  SyncController controller() => SyncController.forTesting(
    synchronize: readOneAlbum,
    classifyFailure: classifySupabaseSyncFailure,
    statusStore: SyncStatusStore.forTesting(
      getString: (_) async => null,
      setString: (key, value) async => saved.add(value),
    ),
  );

  test('a server that never answers ends the sync as a timeout', () async {
    respond = held.add;
    final sync = controller();
    addTearDown(sync.dispose);

    final finished = await sync
        .synchronize('user-1')
        .timeout(const Duration(seconds: 10));

    expect(finished, isFalse);
    expect(sync.isSyncing, isFalse);
    expect(sync.status, SyncStatus.error);
    expect(sync.failureKind, SyncFailureKind.timeout);
    expect(sync.lastSuccessfulSync, isNull);
    expect(saved, isEmpty, reason: 'Last synced is never recorded');
  });

  test('a server failure is reported as one', () async {
    reply(503, {'message': 'unavailable'});
    final sync = controller();
    addTearDown(sync.dispose);

    expect(await sync.synchronize('user-1'), isFalse);
    expect(sync.failureKind, SyncFailureKind.server);
    expect(sync.lastSuccessfulSync, isNull);
  });

  test('an authentication failure asks to sign in again', () async {
    reply(401, {'code': 'PGRST301', 'message': 'JWT expired'});
    final sync = controller();
    addTearDown(sync.dispose);

    expect(await sync.synchronize('user-1'), isFalse);
    expect(sync.failureKind, SyncFailureKind.signIn);
    expect(sync.lastSuccessfulSync, isNull);
  });

  test('after a timeout, the next attempt succeeds and records it', () async {
    respond = held.add;
    final sync = controller();
    addTearDown(sync.dispose);

    expect(await sync.synchronize('user-1'), isFalse);

    reply(200, <Object>[]);
    expect(await sync.synchronize('user-1'), isTrue);

    expect(sync.status, SyncStatus.success);
    expect(sync.failureKind, isNull);
    expect(sync.lastSuccessfulSync, DateTime.utc(2026, 10, 25));
    expect(saved, hasLength(1));
  });
}
