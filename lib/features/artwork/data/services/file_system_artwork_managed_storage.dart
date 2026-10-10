import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../application/services/artwork_managed_storage.dart';
import '../../application/services/owned_artwork_managed_storage.dart';

typedef ArtworkStorageDirectoryProvider = Future<Directory> Function();

class FileSystemArtworkManagedStorage
    implements ArtworkManagedStorage, OwnedArtworkManagedStorage {
  FileSystemArtworkManagedStorage({
    ArtworkStorageDirectoryProvider? applicationSupportDirectoryProvider,
    Uuid? uuid,
    String Function()? fileIdGenerator,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory,
       _uuid = uuid ?? const Uuid(),
       // ignore: prefer_initializing_formals
       _fileIdGenerator = fileIdGenerator;

  final ArtworkStorageDirectoryProvider _applicationSupportDirectoryProvider;
  final Uuid _uuid;
  final String Function()? _fileIdGenerator;

  @override
  Future<String> importArtwork(String sourceFilePath) async {
    final trimmedPath = sourceFilePath.trim();

    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        sourceFilePath,
        'sourceFilePath',
        'Artwork source file path cannot be empty.',
      );
    }

    final sourceFile = File(trimmedPath);

    if (!await sourceFile.exists()) {
      throw StateError('Artwork source file does not exist: $trimmedPath');
    }

    final supportDirectory = await _applicationSupportDirectoryProvider();
    final artworkDirectory = Directory(
      path.join(supportDirectory.path, 'sonus', 'artwork'),
    );

    await artworkDirectory.create(recursive: true);

    final extension = path.extension(trimmedPath).toLowerCase();
    final fileId = _fileIdGenerator?.call() ?? _uuid.v4();

    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(fileId)) {
      throw StateError('Invalid managed artwork file identifier.');
    }

    final fileName = 'artwork_$fileId$extension';
    final destinationPath = path.join(artworkDirectory.path, fileName);
    final destination = File(destinationPath);

    // An existing destination must never be overwritten or deleted.
    // Only a successfully created file belongs to this operation.
    await destination.create(exclusive: true);

    try {
      final output = await destination.open(mode: FileMode.append);

      try {
        await for (final chunk in sourceFile.openRead()) {
          await output.writeFrom(chunk);
        }

        await output.flush();
      } finally {
        await output.close();
      }

      return destinationPath;
    } catch (_) {
      try {
        await destination.delete();
      } catch (_) {
        // Preserve the original import failure.
      }

      rethrow;
    }
  }

  @override
  Future<OwnedArtworkImport> importOwnedArtwork(String sourceFilePath) async {
    final managedPath = await importArtwork(sourceFilePath);
    return _FileSystemOwnedArtworkImport(managedPath);
  }
}

class _FileSystemOwnedArtworkImport implements OwnedArtworkImport {
  const _FileSystemOwnedArtworkImport(this.filePath);

  @override
  final String filePath;

  @override
  Future<void> discard() async {
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }
  }
}
