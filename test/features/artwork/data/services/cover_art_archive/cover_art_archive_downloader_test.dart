import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_binary_transport.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_downloader.dart';

void main() {
  late Directory root;
  late _FakeBinaryTransport transport;
  late CoverArtArchiveDownloader downloader;

  final frontUrl = Uri.parse(
    'https://coverartarchive.org/release/'
    '12345678-1234-1234-1234-123456789abc/front',
  );

  const pngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];

  const jpegBytes = <int>[255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1];

  const webpBytes = <int>[82, 73, 70, 70, 4, 0, 0, 0, 87, 69, 66, 80];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_cover_test_');
    transport = _FakeBinaryTransport();

    downloader = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/1.0 (test)',
      temporaryDirectoryProvider: () async => root,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> expectNoTemporaryFiles() async {
    expect(await root.list().toList(), isEmpty);
  }

  test('downloads PNG and cleans up after use', () async {
    transport.responses.add(_response(pngBytes));

    final result = await downloader.download(frontUrl);

    expect(result.format, CoverArtImageFormat.png);
    expect(result.byteLength, pngBytes.length);
    expect(result.filePath, endsWith('artwork.png'));
    expect(await File(result.filePath).readAsBytes(), pngBytes);
    expect(transport.requestedUris, [frontUrl]);

    await result.deleteTemporaryFiles();

    expect(await File(result.filePath).exists(), isFalse);
    await expectNoTemporaryFiles();
  });

  test('recognizes JPEG and WebP formats', () async {
    for (final entry in <(List<int>, CoverArtImageFormat)>[
      (jpegBytes, CoverArtImageFormat.jpeg),
      (webpBytes, CoverArtImageFormat.webp),
    ]) {
      transport.responses.add(_response(entry.$1));

      final result = await downloader.download(frontUrl);

      expect(result.format, entry.$2);
      await result.deleteTemporaryFiles();
    }

    await expectNoTemporaryFiles();
  });

  test('rejects insecure initial URL before network', () async {
    await expectLater(
      downloader.download(Uri.parse('http://coverartarchive.org/front')),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestedUris, isEmpty);
    await expectNoTemporaryFiles();
  });

  test('rejects unrelated host and nonstandard HTTPS port', () async {
    for (final uri in [
      Uri.parse('https://example.com/front'),
      Uri.parse('https://coverartarchive.org.evil.test/front'),
      Uri.parse('https://coverartarchive.org:8443/front'),
      Uri.parse('https://user:pass@coverartarchive.org/front'),
    ]) {
      await expectLater(
        downloader.download(uri),
        throwsA(isA<CoverArtDownloadException>()),
      );
    }

    expect(transport.requestedUris, isEmpty);
  });

  test('follows trusted redirect', () async {
    final destination = Uri.parse(
      'https://ia801.example.archive.org/download/cover.jpg',
    );

    transport.responses.add(
      _response(const [], statusCode: 302, location: destination.toString()),
    );
    transport.responses.add(_response(jpegBytes));

    final result = await downloader.download(frontUrl);

    expect(result.format, CoverArtImageFormat.jpeg);
    expect(transport.requestedUris, [frontUrl, destination]);

    await result.deleteTemporaryFiles();
    await expectNoTemporaryFiles();
  });

  test('blocks redirect to untrusted host', () async {
    transport.responses.add(
      _response(
        const [],
        statusCode: 302,
        location: 'https://evil.example/artwork.jpg',
      ),
    );

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestedUris, [frontUrl]);
    await expectNoTemporaryFiles();
  });

  test('blocks HTTPS downgrade redirect', () async {
    transport.responses.add(
      _response(
        const [],
        statusCode: 302,
        location: 'http://archive.org/download/cover.jpg',
      ),
    );

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestedUris, [frontUrl]);
  });

  test('enforces redirect limit', () async {
    transport.responses.add(
      _response(const [], statusCode: 302, location: '/another'),
    );
    transport.responses.add(
      _response(const [], statusCode: 302, location: '/again'),
    );

    final limited = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/Test',
      maximumRedirects: 1,
      temporaryDirectoryProvider: () async => root,
    );

    await expectLater(
      limited.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestedUris, hasLength(2));
    await expectNoTemporaryFiles();
  });

  test('rejects declared oversized download before writing', () async {
    transport.responses.add(
      _response(pngBytes, contentLength: 10 * 1024 * 1024 + 1),
    );

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    await expectNoTemporaryFiles();
  });

  test('enforces streaming limit and deletes partial file', () async {
    final limited = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/Test',
      maximumBytes: 16,
      temporaryDirectoryProvider: () async => root,
    );

    transport.responses.add(
      CoverArtBinaryResponse(
        statusCode: 200,
        bytes: Stream<List<int>>.fromIterable([
          pngBytes,
          List<int>.filled(10, 0),
        ]),
      ),
    );

    await expectLater(
      limited.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    await expectNoTemporaryFiles();
  });

  test('rejects HTML masquerading as an image', () async {
    transport.responses.add(
      _response('<html>error</html>'.codeUnits, contentType: 'image/png'),
    );

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    await expectNoTemporaryFiles();
  });

  test('cleans up partial file when stream fails', () async {
    transport.responses.add(
      CoverArtBinaryResponse(
        statusCode: 200,
        bytes: Stream<List<int>>.fromIterable([pngBytes]).followedByError(),
      ),
    );

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<StateError>()),
    );

    await expectNoTemporaryFiles();
  });

  test('recognizes a PNG signature split across stream chunks', () async {
    transport.responses.add(
      CoverArtBinaryResponse(
        statusCode: 200,
        bytes: Stream<List<int>>.fromIterable([
          pngBytes.sublist(0, 2),
          pngBytes.sublist(2, 5),
          pngBytes.sublist(5, 9),
          pngBytes.sublist(9),
        ]),
      ),
    );

    final result = await downloader.download(frontUrl);

    expect(result.format, CoverArtImageFormat.png);
    expect(result.byteLength, pngBytes.length);
    expect(await File(result.filePath).readAsBytes(), pngBytes);

    await result.deleteTemporaryFiles();
    await expectNoTemporaryFiles();
  });

  test('rejects an empty HTTP 200 response and cleans up', () async {
    transport.responses.add(_response(const []));

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    await expectNoTemporaryFiles();
  });

  test('rejects redirect without Location header', () async {
    transport.responses.add(_response(const [], statusCode: 302));

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestedUris, [frontUrl]);
    await expectNoTemporaryFiles();
  });
  test('cleans up when the image stream stalls', () async {
    final limited = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/Test',
      inactivityTimeout: const Duration(milliseconds: 30),
      temporaryDirectoryProvider: () async => root,
    );

    transport.responses.add(
      CoverArtBinaryResponse(
        statusCode: 200,
        bytes: (() async* {
          yield pngBytes;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        })(),
      ),
    );

    await expectLater(
      limited.download(frontUrl),
      throwsA(isA<TimeoutException>()),
    );

    await expectNoTemporaryFiles();
  });
  test('rejects a continuous stream after the overall deadline', () async {
    final limited = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/Test',
      inactivityTimeout: const Duration(seconds: 1),
      overallTimeout: const Duration(milliseconds: 60),
      temporaryDirectoryProvider: () async => root,
    );

    Stream<List<int>> slowStream() async* {
      yield pngBytes;

      for (var index = 0; index < 10; index++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        yield const [0];
      }
    }

    transport.responses.add(
      CoverArtBinaryResponse(statusCode: 200, bytes: slowStream()),
    );

    await expectLater(
      limited.download(frontUrl),
      throwsA(isA<TimeoutException>()),
    );

    await expectNoTemporaryFiles();
  });
  test('cancels an active image stream and removes partial files', () async {
    final token = CoverArtCancellationToken();
    final listening = Completer<void>();
    final stopped = Completer<void>();

    final controller = StreamController<List<int>>(
      onListen: () => listening.complete(),
      onCancel: () => stopped.complete(),
    );

    addTearDown(() async {
      await controller.close();
    });

    transport.responses.add(
      CoverArtBinaryResponse(statusCode: 200, bytes: controller.stream),
    );

    final pending = downloader.download(frontUrl, cancellationToken: token);

    await listening.future.timeout(const Duration(seconds: 3));

    controller.add(pngBytes);
    token.cancel();

    await expectLater(
      pending.timeout(const Duration(seconds: 3)),
      throwsA(isA<CoverArtCancelledException>()),
    );

    await stopped.future.timeout(const Duration(seconds: 3));
    await expectNoTemporaryFiles();
  });
  test('cancellation during temporary-directory creation cleans up', () async {
    final token = CoverArtCancellationToken();
    final providerEntered = Completer<void>();
    final releaseProvider = Completer<void>();

    transport.responses.add(
      CoverArtBinaryResponse(
        statusCode: 200,
        bytes: Stream<List<int>>.value(pngBytes),
      ),
    );

    final limited = CoverArtArchiveDownloader(
      transport: transport,
      userAgent: 'Sonus/Test',
      temporaryDirectoryProvider: () async {
        providerEntered.complete();
        await releaseProvider.future;
        return root;
      },
    );

    final pending = limited.download(frontUrl, cancellationToken: token);

    await providerEntered.future.timeout(const Duration(seconds: 3));

    token.cancel();
    releaseProvider.complete();

    await expectLater(
      pending.timeout(const Duration(seconds: 3)),
      throwsA(isA<CoverArtCancelledException>()),
    );

    await expectNoTemporaryFiles();
  });
  test('late HTTP response is disposed after overall timeout', () async {
    final pendingTransport = _PendingBinaryTransport();
    final streamCancelled = Completer<void>();

    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!streamCancelled.isCompleted) {
          streamCancelled.complete();
        }
      },
    );

    addTearDown(() async {
      await controller.close();
    });

    final limited = CoverArtArchiveDownloader(
      transport: pendingTransport,
      userAgent: 'Sonus/Test',
      overallTimeout: const Duration(milliseconds: 100),
      temporaryDirectoryProvider: () async => root,
    );

    await expectLater(
      limited.download(frontUrl).timeout(const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );

    expect(pendingTransport.receivedToken, isNotNull);
    expect(pendingTransport.receivedToken!.isCancelled, isTrue);

    pendingTransport.pending.complete(
      CoverArtBinaryResponse(statusCode: 200, bytes: controller.stream),
    );

    await streamCancelled.future.timeout(const Duration(seconds: 3));

    await expectNoTemporaryFiles();
  });
  test('overall deadline cancels a pending HTTP request', () async {
    final pendingTransport = _PendingBinaryTransport();

    final limited = CoverArtArchiveDownloader(
      transport: pendingTransport,
      userAgent: 'Sonus/Test',
      overallTimeout: const Duration(milliseconds: 100),
      temporaryDirectoryProvider: () async => root,
    );

    await expectLater(
      limited.download(frontUrl).timeout(const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );

    expect(pendingTransport.requestCount, 1);
    expect(pendingTransport.receivedToken, isNotNull);
    expect(pendingTransport.receivedToken!.isCancelled, isTrue);

    await expectNoTemporaryFiles();
  });
  test('rejects non-success HTTP response', () async {
    transport.responses.add(_response(const [], statusCode: 503));

    await expectLater(
      downloader.download(frontUrl),
      throwsA(isA<CoverArtDownloadException>()),
    );

    await expectNoTemporaryFiles();
  });
}

CoverArtBinaryResponse _response(
  List<int> bytes, {
  int statusCode = 200,
  int? contentLength,
  String? contentType,
  String? location,
}) {
  return CoverArtBinaryResponse(
    statusCode: statusCode,
    bytes: Stream<List<int>>.value(bytes),
    contentLength: contentLength,
    contentType: contentType,
    location: location,
  );
}

class _PendingBinaryTransport implements CoverArtBinaryTransport {
  final Completer<CoverArtBinaryResponse> pending =
      Completer<CoverArtBinaryResponse>();

  int requestCount = 0;
  CoverArtCancellationToken? receivedToken;

  @override
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  }) {
    requestCount++;
    receivedToken = cancellationToken;
    return pending.future;
  }
}

class _FakeBinaryTransport implements CoverArtBinaryTransport {
  final List<CoverArtBinaryResponse> responses = [];
  final List<Uri> requestedUris = [];

  @override
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  }) async {
    requestedUris.add(uri);
    if (responses.isEmpty) {
      throw StateError('No fake response configured.');
    }
    return responses.removeAt(0);
  }
}

extension _ErrorStream on Stream<List<int>> {
  Stream<List<int>> followedByError() async* {
    yield* this;
    throw StateError('Simulated stream failure');
  }
}
