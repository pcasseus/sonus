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

  test('owned import preserves the original source', () async {
    final source = File(path.join(tempDirectory.path, 'owned.png'));
    await source.writeAsBytes([1, 2, 3, 4]);

    final storage = createStorage();
    final owned = await storage.importOwnedArtwork(source.path);

    expect(owned.filePath, isNot(source.path));
    expect(await File(owned.filePath).exists(), isTrue);
    expect(await File(owned.filePath).readAsBytes(), [1, 2, 3, 4]);
    expect(await source.exists(), isTrue);

    await owned.discard();

    expect(await File(owned.filePath).exists(), isFalse);
    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });

  test('discarding one owned import preserves another', () async {
    final source = File(path.join(tempDirectory.path, 'shared.jpg'));
    await source.writeAsBytes([5, 6, 7]);

    final storage = createStorage();
    final first = await storage.importOwnedArtwork(source.path);
    final second = await storage.importOwnedArtwork(source.path);

    expect(first.filePath, isNot(second.filePath));

    await first.discard();

    expect(await File(first.filePath).exists(), isFalse);
    expect(await File(second.filePath).exists(), isTrue);
    expect(await source.exists(), isTrue);
    expect(await File(second.filePath).readAsBytes(), [5, 6, 7]);
  });

  test('owned import discard is idempotent', () async {
    final source = File(path.join(tempDirectory.path, 'repeat.webp'));
    await source.writeAsBytes([8, 9, 10]);

    final owned = await createStorage().importOwnedArtwork(source.path);

    await owned.discard();
    await owned.discard();

    expect(await File(owned.filePath).exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('filename collision preserves existing artwork', () async {
    final firstSource = File(path.join(tempDirectory.path, 'first.png'));
    final secondSource = File(path.join(tempDirectory.path, 'second.png'));

    await firstSource.writeAsBytes([1, 2, 3]);
    await secondSource.writeAsBytes([9, 8, 7]);

    final storage = FileSystemArtworkManagedStorage(
      applicationSupportDirectoryProvider: () async => supportDirectory,
      fileIdGenerator: () => 'fixed',
    );

    final first = await storage.importOwnedArtwork(firstSource.path);

    expect(await File(first.filePath).readAsBytes(), [1, 2, 3]);

    await expectLater(
      storage.importOwnedArtwork(secondSource.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(await File(first.filePath).exists(), isTrue);
    expect(await File(first.filePath).readAsBytes(), [1, 2, 3]);

    expect(await firstSource.readAsBytes(), [1, 2, 3]);
    expect(await secondSource.readAsBytes(), [9, 8, 7]);

    final managedDirectory = Directory(
      path.join(supportDirectory.path, 'sonus', 'artwork'),
    );

    expect(await managedDirectory.list().toList(), hasLength(1));

    await first.discard();

    expect(await File(first.filePath).exists(), isFalse);
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
