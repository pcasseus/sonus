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
}
