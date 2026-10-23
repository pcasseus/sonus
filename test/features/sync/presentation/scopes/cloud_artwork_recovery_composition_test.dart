import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_image_validator.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/presentation/scopes/cloud_artwork_recovery_composition.dart';

// SN-47B3: the exact artwork recovery chain SyncScope uses, driven against a
// local loopback server: Supabase streaming download, image decoding and
// managed artwork storage. No real Supabase project is contacted.
void main() {
  // Image decoding needs the binding; the loopback server needs real HTTP,
  // which the test binding otherwise replaces with a 400 responder.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late HttpServer server;
  late List<String> requestedPaths;
  late List<int> body;
  late SupabaseClient client;
  late Directory root;

  setUp(() async {
    requestedPaths = [];
    body = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requestedPaths.add(Uri.decodeFull(request.uri.path));
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(body);
      await request.response.close();
    });

    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    root = await Directory.systemTemp.createTemp('sonus_recovery_chain_');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  Future<List<int>> png() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final image = await recorder.endRecording().toImage(2, 2);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Directory downloads() => Directory(p.join(root.path, 'downloads'));
  Directory managed() => Directory(p.join(root.path, 'sonus', 'artwork'));

  Future<String> downloadDirectory() async {
    return (await downloads().create(recursive: true)).path;
  }

  final record = CloudArtworkAssetRecord(
    id: 'artwork_1',
    userId: 'user-1',
    storageObjectKey: 'user-1/artwork_1/v1.png',
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );

  test('recovers a valid image into managed artwork storage', () async {
    body = await png();

    final owned = await createCloudArtworkRecovery(
      client: client,
      downloadDirectory: downloadDirectory,
      managedArtworkDirectory: () async => root,
    ).recover(record);

    expect(requestedPaths.single, endsWith('/artwork/user-1/artwork_1/v1.png'));
    expect(p.dirname(owned.filePath), managed().path);
    expect(p.extension(owned.filePath), '.png');
    expect(await File(owned.filePath).readAsBytes(), body);
    expect(downloads().listSync(), isEmpty);
  });

  test('rejects bytes that do not decode as an image', () async {
    body = List<int>.filled(64, 1);

    await expectLater(
      createCloudArtworkRecovery(
        client: client,
        downloadDirectory: downloadDirectory,
        managedArtworkDirectory: () async => root,
      ).recover(record),
      throwsA(isA<CoverArtImageValidationException>()),
    );

    expect(downloads().listSync(), isEmpty);
    expect(managed().existsSync(), isFalse);
  });
}
