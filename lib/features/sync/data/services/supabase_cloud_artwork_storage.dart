import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../artwork/domain/entities/artwork_asset.dart';
import '../../application/services/cloud_artwork_storage.dart';
import '../contracts/supabase_sync_contract.dart';

/// A cloud artwork download that was refused or could not be completed.
class CloudArtworkDownloadException implements Exception {
  const CloudArtworkDownloadException(this.message);

  final String message;

  @override
  String toString() => 'CloudArtworkDownloadException: $message';
}

class SupabaseCloudArtworkStorage implements CloudArtworkStorage {
  const SupabaseCloudArtworkStorage({
    required this.client,
    this.fileIdGenerator,
  });

  final SupabaseClient client;

  /// Names temporary download files. Defaults to a random UUID.
  final String Function()? fileIdGenerator;

  String _newFileId() => fileIdGenerator?.call() ?? const Uuid().v4();

  @override
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  }) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }

    final filePath = artworkAsset.filePath.trim();

    if (filePath.isEmpty) {
      throw StateError(
        'Artwork ${artworkAsset.id} has an empty local file path.',
      );
    }

    final file = File(filePath);

    if (!await file.exists()) {
      throw StateError('Artwork file does not exist: $filePath');
    }

    final extension = path.extension(filePath);

    if (extension.isEmpty) {
      throw StateError('Artwork ${artworkAsset.id} has no file extension.');
    }

    final objectKey = SupabaseSyncContract.artworkObjectKey(
      userId: trimmedUserId,
      artworkId: artworkAsset.id,
      extension: extension,
    );

    await client.storage
        .from(SupabaseSyncContract.artworkBucket)
        .upload(objectKey, file, fileOptions: const FileOptions(upsert: true));

    return objectKey;
  }

  @override
  Future<String> uploadImmutable({
    required String userId,
    required ArtworkAsset artworkAsset,
    required String version,
  }) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID cannot be empty.');
    }

    final file = await _existingFile(artworkAsset);

    final objectKey = SupabaseSyncContract.versionedArtworkObjectKey(
      userId: trimmedUserId,
      artworkId: artworkAsset.id,
      version: version,
      extension: path.extension(file.path),
    );

    try {
      await client.storage
          .from(SupabaseSyncContract.artworkBucket)
          .upload(
            objectKey,
            file,
            fileOptions: const FileOptions(upsert: false),
          );
    } on StorageException catch (error) {
      // Same attempt identity: an earlier upload whose response was lost.
      if (error.statusCode != '409' && error.error != 'Duplicate') {
        rethrow;
      }
    }

    return objectKey;
  }

  @override
  Future<String> downloadToTemporaryFile({
    required String userId,
    required String artworkId,
    required String objectKey,
    required String directoryPath,
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
    }

    final extension = SupabaseSyncContract.verifiedArtworkObjectKeyExtension(
      userId: userId.trim(),
      artworkId: artworkId.trim(),
      objectKey: objectKey,
    );

    if (extension == null) {
      throw const CloudArtworkDownloadException(
        'Artwork object key does not belong to this artwork.',
      );
    }

    final destination = File(
      path.join(directoryPath, 'cloud_artwork_${_newFileId()}.$extension'),
    );

    // Only a file this call created exclusively is ever written or removed.
    await destination.create(exclusive: true);

    try {
      final output = await destination.open(mode: FileMode.writeOnly);

      try {
        var received = 0;

        await for (final chunk
            in client.storage
                .from(SupabaseSyncContract.artworkBucket)
                .downloadStream(objectKey)) {
          received += chunk.length;

          // Leaving the loop cancels the response stream.
          if (received > maxBytes) {
            throw const CloudArtworkDownloadException(
              'Artwork exceeds the download size limit.',
            );
          }

          await output.writeFrom(chunk);
        }

        if (received == 0) {
          throw const CloudArtworkDownloadException('Artwork is empty.');
        }

        await output.flush();
      } finally {
        await output.close();
      }

      return destination.path;
    } catch (_) {
      try {
        await destination.delete();
      } catch (_) {
        // Preserve the original download failure.
      }

      rethrow;
    }
  }

  @override
  Future<void> deleteObject({
    required String userId,
    required String objectKey,
  }) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty || !objectKey.startsWith('$trimmedUserId/')) {
      throw ArgumentError.value(
        objectKey,
        'objectKey',
        'Artwork object must belong to the user.',
      );
    }

    await client.storage.from(SupabaseSyncContract.artworkBucket).remove([
      objectKey,
    ]);
  }

  Future<File> _existingFile(ArtworkAsset artworkAsset) async {
    final filePath = artworkAsset.filePath.trim();

    if (filePath.isEmpty) {
      throw StateError(
        'Artwork ${artworkAsset.id} has an empty local file path.',
      );
    }

    final file = File(filePath);

    if (!await file.exists()) {
      throw StateError('Artwork file does not exist: $filePath');
    }

    if (path.extension(filePath).isEmpty) {
      throw StateError('Artwork ${artworkAsset.id} has no file extension.');
    }

    return file;
  }
}
