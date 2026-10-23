import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';
import 'package:sonus_next/features/sync/data/services/supabase_cloud_artwork_storage.dart';

// SN-47 A2 item 5: immutable artwork objects, verified against a local
// loopback server. No real Supabase project is contacted.
void main() {
  late HttpServer server;
  late List<({String method, String path, String upsert})> requests;
  late List<(int, Object?)> responses;
  late SupabaseClient client;
  late SupabaseCloudArtworkStorage storage;
  late Directory directory;
  late ArtworkAsset asset;

  setUp(() async {
    requests = [];
    responses = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requests.add((
        method: request.method,
        path: Uri.decodeFull(request.uri.path),
        upsert: request.headers.value('x-upsert') ?? '',
      ));

      final (status, body) = responses.removeAt(0);
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    storage = SupabaseCloudArtworkStorage(client: client);

    directory = await Directory.systemTemp.createTemp('sonus_artwork_');
    final file = File('${directory.path}/cover.PNG')
      ..writeAsBytesSync([1, 2, 3]);
    asset = ArtworkAsset(
      id: 'artwork-1',
      filePath: file.path,
      normalizedPath: file.path,
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('versioned keys are unique per version and keep the owner prefix', () {
    expect(
      SupabaseSyncContract.versionedArtworkObjectKey(
        userId: 'user-1',
        artworkId: 'artwork-1',
        version: 'outbox-1-r2',
        extension: '.PNG',
      ),
      'user-1/artwork-1/outbox-1-r2.png',
    );
    expect(
      () => SupabaseSyncContract.versionedArtworkObjectKey(
        userId: 'user-1',
        artworkId: 'artwork-1',
        version: '../escape',
        extension: '.png',
      ),
      throwsArgumentError,
    );
  });

  test('uploadImmutable never requests an overwrite', () async {
    responses.add((200, {'Key': 'artwork/user-1/artwork-1/v1.png'}));

    final key = await storage.uploadImmutable(
      userId: 'user-1',
      artworkAsset: asset,
      version: 'v1',
    );

    expect(key, 'user-1/artwork-1/v1.png');
    expect(requests.single.method, 'POST');
    expect(
      requests.single.path,
      '/storage/v1/object/artwork/user-1/artwork-1/v1.png',
    );
    expect(requests.single.upsert, 'false');
  });

  test('an existing object for the same version is reused', () async {
    responses.add((
      400,
      {
        'statusCode': '409',
        'error': 'Duplicate',
        'message': 'The resource already exists',
      },
    ));

    final key = await storage.uploadImmutable(
      userId: 'user-1',
      artworkAsset: asset,
      version: 'v1',
    );

    expect(key, 'user-1/artwork-1/v1.png');
  });

  test('other storage failures are surfaced', () async {
    responses.add((
      403,
      {'statusCode': '403', 'error': 'Unauthorized', 'message': 'denied'},
    ));

    await expectLater(
      storage.uploadImmutable(
        userId: 'user-1',
        artworkAsset: asset,
        version: 'v1',
      ),
      throwsA(isA<StorageException>()),
    );
  });

  test('deleteObject only removes the owner\'s objects', () async {
    responses.add((200, <Object?>[]));

    await storage.deleteObject(
      userId: 'user-1',
      objectKey: 'user-1/artwork-1/v1.png',
    );

    expect(requests.single.method, 'DELETE');

    expect(
      () => storage.deleteObject(
        userId: 'user-1',
        objectKey: 'user-2/artwork-1/v1.png',
      ),
      throwsArgumentError,
    );
    expect(requests, hasLength(1));
  });
}
