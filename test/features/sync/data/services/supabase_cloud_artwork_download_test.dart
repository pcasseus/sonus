import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';
import 'package:sonus_next/features/sync/data/services/supabase_cloud_artwork_storage.dart';

// SN-47B3: streaming cloud artwork downloads, verified against a local
// loopback server. No real Supabase project is contacted.
void main() {
  late HttpServer server;
  late List<String> requestedPaths;
  late List<List<int>> chunks;
  late int chunksSent;

  /// Pause between chunks. Socket writes complete once buffered, not once
  /// read, so only pacing shows whether the client stopped early.
  late Duration chunkPause;
  late SupabaseClient client;
  late Directory directory;
  late SupabaseCloudArtworkStorage storage;

  setUp(() async {
    requestedPaths = [];
    chunks = [];
    chunksSent = 0;
    chunkPause = Duration.zero;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requestedPaths.add(Uri.decodeFull(request.uri.path));

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..bufferOutput = false;

      try {
        for (final chunk in chunks) {
          request.response.add(chunk);
          await request.response.flush();
          chunksSent += 1;
          if (chunkPause > Duration.zero) {
            await Future<void>.delayed(chunkPause);
          }
        }

        await request.response.close();
      } catch (_) {
        // The client stopped reading; the connection is gone.
      }
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    directory = await Directory.systemTemp.createTemp('sonus_artwork_dl_');
    storage = SupabaseCloudArtworkStorage(
      client: client,
      fileIdGenerator: () => 'fixed',
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<String> download(String objectKey, {int maxBytes = 1024}) {
    return storage.downloadToTemporaryFile(
      userId: 'user-1',
      artworkId: 'artwork_1',
      objectKey: objectKey,
      directoryPath: directory.path,
      maxBytes: maxBytes,
    );
  }

  List<String> files() => directory.listSync().map((e) => e.path).toList();

  group('key verification', () {
    String? verify(String key) {
      return SupabaseSyncContract.verifiedArtworkObjectKeyExtension(
        userId: 'user-1',
        artworkId: 'artwork_1',
        objectKey: key,
      );
    }

    test('accepts legacy and versioned keys for the same artwork', () {
      expect(verify('user-1/artwork_1.png'), 'png');
      expect(verify('user-1/artwork_1/outbox-1-r2.jpeg'), 'jpeg');
    });

    test('rejects other owners, other artwork and unsafe shapes', () {
      for (final key in [
        'user-2/artwork_1.png',
        'user-1/artwork_10.png',
        'user-1/artwork_1.exe',
        'user-1/artwork_1.PNG',
        'user-1/artwork_1/../x.png',
        'user-1/artwork_1/a/b.png',
        'user-1/artwork_1',
        '/user-1/artwork_1.png',
      ]) {
        expect(verify(key), isNull, reason: key);
      }
    });
  });

  test('streams an approved key into a new temporary file', () async {
    chunks = [
      [1, 2, 3],
      [4, 5],
    ];

    final path = await download('user-1/artwork_1/v1.png');

    expect(
      requestedPaths.single,
      endsWith('/object/artwork/user-1/artwork_1/v1.png'),
    );
    expect(p.basename(path), 'cloud_artwork_fixed.png');
    expect(await File(path).readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('refuses a foreign key before any request', () async {
    await expectLater(
      download('user-2/artwork_1.png'),
      throwsA(isA<CloudArtworkDownloadException>()),
    );

    expect(requestedPaths, isEmpty);
    expect(files(), isEmpty);
  });

  test('stops streaming once the byte limit is passed', () async {
    // 200 paced chunks take a second to send; a client that stops after
    // about 2 KB leaves most of them unsent.
    chunks = List.generate(200, (_) => List<int>.filled(1024, 7));
    chunkPause = const Duration(milliseconds: 5);

    await expectLater(
      download('user-1/artwork_1.png', maxBytes: 1500),
      throwsA(isA<CloudArtworkDownloadException>()),
    );

    // The partial file is removed and the stream was abandoned early.
    expect(files(), isEmpty);
    expect(chunksSent, lessThan(chunks.length));
  });

  test('an empty object is rejected and removed', () async {
    await expectLater(
      download('user-1/artwork_1.png'),
      throwsA(isA<CloudArtworkDownloadException>()),
    );

    expect(files(), isEmpty);
  });

  test('never overwrites an existing file', () async {
    final existing = File(p.join(directory.path, 'cloud_artwork_fixed.png'))
      ..writeAsBytesSync([9, 9, 9]);
    chunks = [
      [1, 2, 3],
    ];

    await expectLater(
      download('user-1/artwork_1.png'),
      throwsA(isA<FileSystemException>()),
    );

    expect(existing.readAsBytesSync(), [9, 9, 9]);
    expect(requestedPaths, isEmpty);
  });
}
