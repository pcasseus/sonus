import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/services/backup_archive_writer.dart';

void main() {
  late Directory root;
  late Directory staging;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_zip_writer_');
    staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    await File(
      path.join(staging.path, 'manifest.json'),
    ).writeAsString('{"formatVersion":1}');

    await File(
      path.join(staging.path, 'library.json'),
    ).writeAsString('{"integrityVersion":1}');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  const writer = BackupArchiveWriter();

  test('creates a ZIP-compatible .sonusbackup with artwork', () async {
    final artwork = Directory(path.join(staging.path, 'artwork'));
    await artwork.create();

    await File(path.join(artwork.path, 'cover.jpg')).writeAsBytes([1, 2, 3, 4]);

    final destination = File(path.join(root.path, 'test.sonusbackup'));

    await writer.write(stagingDirectory: staging, destination: destination);

    expect(await destination.exists(), isTrue);

    final input = InputFileStream(destination.path);

    try {
      final archive = ZipDecoder().decodeStream(input);

      final names = archive.files.map((file) => file.name).toSet();

      expect(names, contains('manifest.json'));
      expect(names, contains('library.json'));
      expect(names, contains('artwork/cover.jpg'));
    } finally {
      await input.close();
    }
  });

  test('refuses to overwrite an existing backup', () async {
    final destination = File(path.join(root.path, 'existing.sonusbackup'));

    await destination.writeAsBytes([9, 8, 7]);

    await expectLater(
      writer.write(stagingDirectory: staging, destination: destination),
      throwsStateError,
    );

    expect(await destination.readAsBytes(), [9, 8, 7]);
  });

  test('rejects staging without required files', () async {
    await File(path.join(staging.path, 'library.json')).delete();

    final destination = File(path.join(root.path, 'invalid.sonusbackup'));

    await expectLater(
      writer.write(stagingDirectory: staging, destination: destination),
      throwsFormatException,
    );

    expect(await destination.exists(), isFalse);
  });

  test('rejects incorrect backup extension', () async {
    final destination = File(path.join(root.path, 'backup.zip'));

    await expectLater(
      writer.write(stagingDirectory: staging, destination: destination),
      throwsArgumentError,
    );

    expect(await destination.exists(), isFalse);
  });
}
