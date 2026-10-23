import 'dart:io';

import '../../../artwork/application/services/owned_artwork_managed_storage.dart';
import '../../domain/models/cloud_records.dart';
import 'cloud_artwork_storage.dart';

/// Recovers the bytes of one live cloud artwork asset as a managed file.
typedef RecoverCloudArtwork =
    Future<OwnedArtworkImport> Function(CloudArtworkAssetRecord record);

typedef ValidateArtworkImage = Future<void> Function(String filePath);

typedef ArtworkDownloadDirectory = Future<String> Function();

/// Downloads cloud artwork into a temporary file, validates it as an image
/// and imports it into managed artwork storage as an owned file.
///
/// Network and decoding work happen here, outside any database
/// transaction. The caller decides whether the returned import is
/// retained and must discard it otherwise.
class CloudArtworkRecoveryService {
  const CloudArtworkRecoveryService({
    required this.cloudArtworkStorage,
    required this.managedStorage,
    required this.validateImage,
    required this.downloadDirectory,
    this.maxBytes = defaultMaxBytes,
  });

  static const int defaultMaxBytes = 10 * 1024 * 1024;

  final CloudArtworkStorage cloudArtworkStorage;
  final OwnedArtworkManagedStorage managedStorage;
  final ValidateArtworkImage validateImage;
  final ArtworkDownloadDirectory downloadDirectory;
  final int maxBytes;

  Future<OwnedArtworkImport> recover(CloudArtworkAssetRecord record) async {
    if (record.isDeleted) {
      throw StateError('A tombstoned cloud artwork is never downloaded.');
    }

    String? temporaryPath;

    try {
      temporaryPath = await cloudArtworkStorage.downloadToTemporaryFile(
        userId: record.userId,
        artworkId: record.id,
        objectKey: record.storageObjectKey,
        directoryPath: await downloadDirectory(),
        maxBytes: maxBytes,
      );

      await validateImage(temporaryPath);

      return await managedStorage.importOwnedArtwork(temporaryPath);
    } finally {
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {
          // A leftover temporary file is not managed artwork. Preserve the
          // recovery outcome.
        }
      }
    }
  }
}
