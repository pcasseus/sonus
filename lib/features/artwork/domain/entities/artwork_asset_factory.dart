import '../../../../core/identity/entity_id.dart';
import '../../../../core/identity/text_normalizer.dart';
import 'artwork_asset.dart';

abstract final class ArtworkAssetFactory {
  static ArtworkAsset create({required String filePath, DateTime? now}) {
    final trimmedPath = filePath.trim();

    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Artwork file path cannot be empty.',
      );
    }

    final timestamp = now ?? DateTime.now();

    return ArtworkAsset(
      id: EntityId.artworkAsset(),
      filePath: trimmedPath,
      normalizedPath: TextNormalizer.normalizePath(trimmedPath),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}
