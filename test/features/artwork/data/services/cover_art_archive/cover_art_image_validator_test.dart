import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_image_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  const validator = CoverArtImageValidator();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_image_validation_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<List<int>> makeValidPng() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      if (data == null) {
        throw StateError('Could not encode PNG fixture.');
      }

      return data.buffer.asUint8List().toList();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('accepts a genuinely decodable PNG', () async {
    final bytes = await makeValidPng();
    final file = await writeFile('valid.png', bytes);

    await validator.validate(file.path);
  });

  test('rejects a truncated PNG signature', () async {
    final file = await writeFile('truncated.png', const [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      0,
    ]);

    await expectLater(
      validator.validate(file.path),
      throwsA(isA<CoverArtImageValidationException>()),
    );
  });

  test('rejects HTML content', () async {
    final file = await writeFile(
      'fake.png',
      '<html>Not an image</html>'.codeUnits,
    );

    await expectLater(
      validator.validate(file.path),
      throwsA(isA<CoverArtImageValidationException>()),
    );
  });

  test('rejects an empty file', () async {
    final file = await writeFile('empty.png', const []);

    await expectLater(
      validator.validate(file.path),
      throwsA(isA<CoverArtImageValidationException>()),
    );
  });

  test('rejects a missing file', () async {
    await expectLater(
      validator.validate('${root.path}${Platform.pathSeparator}missing.png'),
      throwsA(isA<CoverArtImageValidationException>()),
    );
  });

  test('rejects files exceeding the configured limit', () async {
    final file = await writeFile('oversized.png', List<int>.filled(100, 0));

    await expectLater(
      const CoverArtImageValidator(maximumBytes: 50).validate(file.path),
      throwsA(isA<CoverArtImageValidationException>()),
    );
  });
}
