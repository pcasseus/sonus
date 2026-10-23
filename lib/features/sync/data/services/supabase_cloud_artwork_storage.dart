import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../artwork/domain/entities/artwork_asset.dart';
import '../../application/services/cloud_artwork_storage.dart';
import '../contracts/supabase_sync_contract.dart';

class SupabaseCloudArtworkStorage implements CloudArtworkStorage {
  const SupabaseCloudArtworkStorage({required this.client});

  final SupabaseClient client;

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
