import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../application/services/artwork_managed_storage.dart';

typedef ArtworkStorageDirectoryProvider = Future<Directory> Function();

class FileSystemArtworkManagedStorage implements ArtworkManagedStorage {
  FileSystemArtworkManagedStorage({
    ArtworkStorageDirectoryProvider? applicationSupportDirectoryProvider,
    Uuid? uuid,
  }) : _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory,
       _uuid = uuid ?? const Uuid();

  final ArtworkStorageDirectoryProvider _applicationSupportDirectoryProvider;
  final Uuid _uuid;

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
    final fileName = 'artwork_${_uuid.v4()}$extension';
    final destinationPath = path.join(artworkDirectory.path, fileName);

    await sourceFile.copy(destinationPath);

    return destinationPath;
  }
}
