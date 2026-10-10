import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_cancellation.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_binary_transport.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_downloader.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_image_validator.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_validated_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _FakeTransport transport;
  late CoverArtValidatedDownloadService service;

  final imageUri = Uri.parse(
    'https://coverartarchive.org/release/'
    '12345678-1234-1234-1234-123456789abc/front',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'sonus_validated_download_test_',
    );

    transport = _FakeTransport();

    service = CoverArtValidatedDownloadService(
      downloader: CoverArtArchiveDownloader(
        transport: transport,
        userAgent: 'Sonus/1.0 (test)',
        temporaryDirectoryProvider: () async => root,
      ),
      validator: const CoverArtImageValidator(),
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<void> expectEmptyRoot() async {
    expect(await root.list().toList(), isEmpty);
  }

  test('valid decoded image remains available until cleanup', () async {
    final png = await _createPng();
    transport.nextBytes = png;

    final result = await service.download(imageUri);

    expect(result.format, CoverArtImageFormat.png);
    expect(result.byteLength, png.length);
    expect(await File(result.filePath).exists(), isTrue);
    expect(await File(result.filePath).readAsBytes(), png);
    expect(transport.requestCount, 1);

    await result.deleteTemporaryFiles();
    await expectEmptyRoot();
  });

  test('truncated image is rejected and temporary files deleted', () async {
    transport.nextBytes = const [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];

    await expectLater(
      service.download(imageUri),
      throwsA(isA<CoverArtImageValidationException>()),
    );

    expect(transport.requestCount, 1);
    await expectEmptyRoot();
  });

  test('pre-cancelled token prevents downloading', () async {
    final token = CoverArtCancellationToken()..cancel();

    await expectLater(
      service.download(imageUri, cancellationToken: token),
      throwsA(isA<CoverArtCancelledException>()),
    );

    expect(transport.requestCount, 0);
    await expectEmptyRoot();
  });

  test('cancellation during decoding deletes the downloaded file', () async {
    final token = CoverArtCancellationToken();
    transport.nextBytes = await _createPng();

    final cancellingService = CoverArtValidatedDownloadService(
      downloader: CoverArtArchiveDownloader(
        transport: transport,
        userAgent: 'Sonus/1.0 (test)',
        temporaryDirectoryProvider: () async => root,
      ),
      validator: _CancellingValidator(token),
    );

    await expectLater(
      cancellingService.download(imageUri, cancellationToken: token),
      throwsA(isA<CoverArtCancelledException>()),
    );

    expect(token.isCancelled, isTrue);
    expect(transport.requestCount, 1);
    await expectEmptyRoot();
  });
  test('untrusted URL is rejected before network or file creation', () async {
    await expectLater(
      service.download(Uri.parse('https://evil.example/cover.png')),
      throwsA(isA<CoverArtDownloadException>()),
    );

    expect(transport.requestCount, 0);
    await expectEmptyRoot();
  });
}

Future<List<int>> _createPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFF0099FF),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);

  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    if (data == null) {
      throw StateError('Could not encode test image.');
    }

    return data.buffer.asUint8List().toList();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _CancellingValidator extends CoverArtImageValidator {
  const _CancellingValidator(this.token);

  final CoverArtCancellationToken token;

  @override
  Future<void> validate(String filePath) async {
    await super.validate(filePath);
    token.cancel();
  }
}

class _FakeTransport implements CoverArtBinaryTransport {
  List<int> nextBytes = const [];
  int requestCount = 0;

  @override
  Future<CoverArtBinaryResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    CoverArtCancellationToken? cancellationToken,
  }) async {
    requestCount++;

    return CoverArtBinaryResponse(
      statusCode: 200,
      bytes: Stream<List<int>>.value(nextBytes),
      contentLength: nextBytes.length,
      contentType: 'image/png',
    );
  }
}
