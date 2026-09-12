import '../../domain/entities/artwork_asset.dart';

abstract final class ArtworkAssetRowMapper {
  static Map<String, Object?> toRow(ArtworkAsset artworkAsset) {
    return {
      'id': artworkAsset.id,
      'file_path': artworkAsset.filePath,
      'normalized_path': artworkAsset.normalizedPath,
      'created_at': artworkAsset.createdAt.toUtc().toIso8601String(),
      'updated_at': artworkAsset.updatedAt.toUtc().toIso8601String(),
    };
  }

  static ArtworkAsset fromRow(Map<String, Object?> row) {
    return ArtworkAsset(
      id: row['id'] as String,
      filePath: row['file_path'] as String,
      normalizedPath: row['normalized_path'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
