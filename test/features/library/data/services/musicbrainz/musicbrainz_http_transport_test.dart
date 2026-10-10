import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('reads response normally', () async {
    final transport = DartIoMusicBrainzHttpTransport();

    addTearDown(transport.close);

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });

    final response = await transport.get(
      Uri.parse('http://127.0.0.1:${server.port}/metadata'),
      headers: {'User-Agent': 'Sonus/Test'},
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, '{"ok":true}');
  });

  test('times out while waiting for response headers', () async {
    final transport = DartIoMusicBrainzHttpTransport(
      responseHeaderTimeout: const Duration(milliseconds: 50),
    );

    addTearDown(transport.close);

    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      try {
        await request.response.close();
      } catch (_) {
        // Client timeout may already have aborted the request.
      }
    });

    await expectLater(
      transport.get(
        Uri.parse('http://127.0.0.1:${server.port}/slow-headers'),
        headers: {'User-Agent': 'Sonus/Test'},
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('times out while reading response body', () async {
    final transport = DartIoMusicBrainzHttpTransport(
      responseBodyTimeout: const Duration(milliseconds: 50),
    );

    addTearDown(transport.close);

    server.listen((request) async {
      request.response.headers.chunkedTransferEncoding = true;
      request.response.write('{"partial":');
      await request.response.flush();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      try {
        request.response.write('true}');
        await request.response.close();
      } catch (_) {
        // Client timeout may already have closed the connection.
      }
    });

    await expectLater(
      transport.get(
        Uri.parse('http://127.0.0.1:${server.port}/slow-body'),
        headers: {'User-Agent': 'Sonus/Test'},
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('rejects non-positive timeout configuration', () {
    expect(
      () => DartIoMusicBrainzHttpTransport(responseBodyTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
