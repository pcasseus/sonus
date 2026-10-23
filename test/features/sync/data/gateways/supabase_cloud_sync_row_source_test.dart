import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/sync/data/gateways/supabase_cloud_sync_row_source.dart';

// SN-47B2: the production by-id read used for deferred replay, verified
// against a local loopback server. No real Supabase project is contacted.
void main() {
  late HttpServer server;
  late List<Uri> requests;
  late SupabaseClient client;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    server.listen((request) async {
      requests.add(request.uri);

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode([
            {'id': 'album-1', 'user_id': 'user-1'},
          ]),
        );
      await request.response.close();
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('readById filters by owner and id', () async {
    final rows = await SupabaseClientCloudSyncRowSource(
      client: client,
    ).readById(table: 'albums', userId: 'user-1', id: 'album-1');

    expect(rows.single['id'], 'album-1');

    final uri = requests.single;
    expect(uri.path, '/rest/v1/albums');
    expect(uri.queryParameters['user_id'], 'eq.user-1');
    expect(uri.queryParameters['id'], 'eq.album-1');
    expect(uri.queryParameters['limit'], '2');
  });
}
