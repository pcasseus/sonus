import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

// Verifies the PostgREST requests behind SN-47 H3 against a local
// loopback server. No real Supabase project is contacted.
void main() {
  late HttpServer server;
  late List<_Captured> requests;
  late List<Object?> responses;
  late SupabaseClient client;
  late SupabaseCloudSyncGateway gateway;

  setUp(() async {
    requests = [];
    responses = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add(
        _Captured(
          method: request.method,
          uri: request.uri,
          prefer: request.headers.value('prefer') ?? '',
          body: body.isEmpty ? null : jsonDecode(body),
        ),
      );

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(responses.removeAt(0)));
      await request.response.close();
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    gateway = SupabaseCloudSyncGateway(client: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('insertIfAbsent ignores duplicates instead of merging', () async {
    responses.add([
      {'server_revision': 1},
    ]);

    final result = await gateway.insertIfAbsent(_album());

    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 1);

    final insert = requests.single;
    expect(insert.method, 'POST');
    expect(insert.uri.path, '/rest/v1/albums');
    expect(insert.uri.queryParameters['on_conflict'], 'id');
    expect(insert.prefer, contains('resolution=ignore-duplicates'));
    expect(insert.prefer, isNot(contains('merge-duplicates')));
  });

  test('insertIfAbsent reports an existing row as a conflict', () async {
    responses
      ..add(<Object?>[])
      ..add([
        {'server_revision': 7},
      ]);

    final result = await gateway.insertIfAbsent(_album());

    expect(result.outcome, CloudConditionalWriteOutcome.conflict);
    expect(result.serverRevision, 7);
    expect(requests, hasLength(2));
    expect(requests[1].method, 'GET');
    expect(requests[1].uri.queryParameters['user_id'], 'eq.user-1');
    expect(requests[1].uri.queryParameters['id'], 'eq.album-1');
  });

  test('updateIfRevision is a single compare-and-set PATCH', () async {
    responses.add([
      {'server_revision': 5},
    ]);

    final result = await gateway.updateIfRevision(
      _album(),
      expectedServerRevision: 4,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.applied);
    expect(result.serverRevision, 5);

    final update = requests.single;
    expect(update.method, 'PATCH');
    expect(update.uri.path, '/rest/v1/albums');
    expect(update.uri.queryParameters['user_id'], 'eq.user-1');
    expect(update.uri.queryParameters['id'], 'eq.album-1');
    expect(update.uri.queryParameters['server_revision'], 'eq.4');
    expect(update.uri.queryParameters['deleted_at'], 'is.null');

    final body = update.body as Map<String, dynamic>;
    expect(body['title'], 'Album');
    expect(
      body.keys,
      isNot(anyOf(contains('id'), contains('user_id'), contains('deleted_at'))),
    );
    expect(body.containsKey('created_at'), isFalse);
  });

  test('updateIfRevision reports a missing row as not found', () async {
    responses
      ..add(<Object?>[])
      ..add(<Object?>[]);

    final result = await gateway.updateIfRevision(
      _album(),
      expectedServerRevision: 4,
    );

    expect(result.outcome, CloudConditionalWriteOutcome.notFound);
    expect(result.serverRevision, isNull);
  });

  test('conditional writes reject tombstones before any request', () async {
    final tombstone = CloudAlbumRecord(
      id: 'album-1',
      userId: 'user-1',
      artistId: 'artist-1',
      title: 'Album',
      canonicalTitle: 'album',
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 21),
      deletedAt: DateTime.utc(2026, 10, 21),
    );

    expect(() => gateway.insertIfAbsent(tombstone), throwsArgumentError);
    expect(
      () => gateway.updateIfRevision(tombstone, expectedServerRevision: 1),
      throwsArgumentError,
    );
    expect(requests, isEmpty);
  });
}

CloudAlbumRecord _album() {
  return CloudAlbumRecord(
    id: 'album-1',
    userId: 'user-1',
    artistId: 'artist-1',
    title: 'Album',
    canonicalTitle: 'album',
    createdAt: DateTime.utc(2026, 10, 20),
    updatedAt: DateTime.utc(2026, 10, 21),
  );
}

class _Captured {
  const _Captured({
    required this.method,
    required this.uri,
    required this.prefer,
    required this.body,
  });

  final String method;
  final Uri uri;
  final String prefer;
  final Object? body;
}
