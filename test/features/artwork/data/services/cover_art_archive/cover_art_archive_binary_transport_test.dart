import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_binary_transport.dart';

void main() {
  late HttpServer server;
  late DartIoCoverArtBinaryTransport transport;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    transport = DartIoCoverArtBinaryTransport();
  });

  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });

  test('streams binary content and exposes image headers', () async {
    server.listen((request) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = 4;
      request.response.add([137, 80, 78, 71]);
      request.response.close();
    });

    final response = await transport.get(
      Uri.parse('http://127.0.0.1:${server.port}/image'),
      headers: {'User-Agent': 'Sonus/Test'},
    );

    final bytes = await response.bytes.expand((chunk) => chunk).toList();

    expect(response.statusCode, 200);
    expect(response.contentType, 'image/png');
    expect(response.contentLength, 4);
    expect(bytes, [137, 80, 78, 71]);
  });

  test('times out while waiting for response headers', () async {
    transport.close();

    transport = DartIoCoverArtBinaryTransport(
      responseHeaderTimeout: const Duration(milliseconds: 50),
    );

    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      try {
        await request.response.close();
      } catch (_) {
        // The timeout may have already aborted the connection.
      }
    });

    await expectLater(
      transport.get(
        Uri.parse('http://127.0.0.1:${server.port}/slow'),
        headers: {'User-Agent': 'Sonus/Test'},
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
  test('cancels an individual request while waiting for headers', () async {
    final received = Completer<void>();
    final token = CoverArtCancellationToken();

    server.listen((request) {
      if (!received.isCompleted) {
        received.complete();
      }

      // Deliberately leave the response open until the client aborts.
    });

    final pending = transport.get(
      Uri.parse('http://127.0.0.1:${server.port}/pending'),
      headers: {'User-Agent': 'Sonus/Test'},
      cancellationToken: token,
    );

    await received.future.timeout(const Duration(seconds: 3));

    token.cancel();

    await expectLater(
      pending.timeout(const Duration(seconds: 3)),
      throwsA(isA<CoverArtCancelledException>()),
    );
  });

  test('cancelling one request does not interrupt another', () async {
    final slowReceived = Completer<void>();
    final token = CoverArtCancellationToken();

    server.listen((request) async {
      if (request.uri.path == '/slow') {
        if (!slowReceived.isCompleted) {
          slowReceived.complete();
        }
        return;
      }

      request.response.add([137, 80, 78, 71]);
      await request.response.close();
    });

    final slow = transport.get(
      Uri.parse('http://127.0.0.1:${server.port}/slow'),
      headers: {'User-Agent': 'Sonus/Test'},
      cancellationToken: token,
    );

    await slowReceived.future.timeout(const Duration(seconds: 3));

    final fast = await transport
        .get(
          Uri.parse('http://127.0.0.1:${server.port}/fast'),
          headers: {'User-Agent': 'Sonus/Test'},
        )
        .timeout(const Duration(seconds: 3));

    token.cancel();

    await expectLater(
      slow.timeout(const Duration(seconds: 3)),
      throwsA(isA<CoverArtCancelledException>()),
    );

    expect(fast.statusCode, HttpStatus.ok);
    expect(await fast.bytes.expand((chunk) => chunk).toList(), [
      137,
      80,
      78,
      71,
    ]);
  });
  test('does not automatically follow redirects', () async {
    var requests = 0;

    server.listen((request) {
      requests++;

      if (request.uri.path == '/redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/destination',
        );
      } else {
        request.response.statusCode = HttpStatus.ok;
      }

      request.response.close();
    });

    final response = await transport.get(
      Uri.parse('http://127.0.0.1:${server.port}/redirect'),
      headers: {'User-Agent': 'Sonus/Test'},
    );

    await response.bytes.drain<void>();

    expect(response.statusCode, HttpStatus.found);
    expect(response.location, '/destination');
    expect(requests, 1);
  });
}
