import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/artwork/data/services/file_system_artwork_managed_storage.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory tempDirectory;
  late Directory supportDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sonus_artwork_storage_test_',
    );

    supportDirectory = Directory(path.join(tempDirectory.path, 'support'));

    await supportDirectory.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  FileSystemArtworkManagedStorage createStorage() {
    return FileSystemArtworkManagedStorage(
      applicationSupportDirectoryProvider: () async => supportDirectory,
      uuid: const Uuid(),
    );
  }

  test('copies artwork into Sonus-managed artwork directory', () async {
    final sourceFile = File(path.join(tempDirectory.path, 'Cover.JPG'));

    await sourceFile.writeAsBytes([1, 2, 3, 4]);

    final storage = createStorage();

    final managedPath = await storage.importArtwork(sourceFile.path);

    final managedFile = File(managedPath);

    expect(await managedFile.exists(), isTrue);
    expect(
      path.dirname(managedPath),
      path.join(supportDirectory.path, 'sonus', 'artwork'),
    );
    expect(path.basename(managedPath), startsWith('artwork_'));
    expect(path.extension(managedPath), '.jpg');
    expect(await managedFile.readAsBytes(), [1, 2, 3, 4]);
  });

  test('preserves source file after import', () async {
    final sourceFile = File(path.join(tempDirectory.path, 'artist.png'));

    await sourceFile.writeAsString('artwork-data');

    final storage = createStorage();

    await storage.importArtwork(sourceFile.path);

    expect(await sourceFile.exists(), isTrue);
    expect(await sourceFile.readAsString(), 'artwork-data');
  });

  test('creates managed artwork directory recursively', () async {
    final nestedSupportDirectory = Directory(
      path.join(tempDirectory.path, 'missing', 'support'),
    );

    final sourceFile = File(path.join(tempDirectory.path, 'album.webp'));

    await sourceFile.writeAsBytes([9, 8, 7]);

    final storage = FileSystemArtworkManagedStorage(
      applicationSupportDirectoryProvider: () async => nestedSupportDirectory,
      uuid: const Uuid(),
    );

    final managedPath = await storage.importArtwork(sourceFile.path);

    expect(await File(managedPath).exists(), isTrue);
    expect(
      await Directory(
        path.join(nestedSupportDirectory.path, 'sonus', 'artwork'),
      ).exists(),
      isTrue,
    );
  });

  test('rejects blank source path', () async {
    final storage = createStorage();

    await expectLater(
      () => storage.importArtwork('   '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects missing source file', () async {
    final storage = createStorage();

    final missingPath = path.join(tempDirectory.path, 'missing.jpg');

    await expectLater(
      () => storage.importArtwork(missingPath),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Artwork source file does not exist: $missingPath',
        ),
      ),
    );
  });

  test('creates a distinct managed file for repeated imports', () async {
    final sourceFile = File(path.join(tempDirectory.path, 'shared.jpeg'));

    await sourceFile.writeAsBytes([5, 6, 7]);

    final storage = createStorage();

    final firstPath = await storage.importArtwork(sourceFile.path);
    final secondPath = await storage.importArtwork(sourceFile.path);

    expect(firstPath, isNot(secondPath));
    expect(await File(firstPath).exists(), isTrue);
    expect(await File(secondPath).exists(), isTrue);
  });
}
