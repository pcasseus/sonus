import '../entities/artwork_crop.dart';

/// Remembered crops (device-local; see ArtworkCropSchema).
abstract interface class ArtworkCropRepository {
  Future<ArtworkCrop?> get(ArtworkCropTarget target, String targetId);

  /// Inserts or replaces the crop for its target.
  Future<void> save(ArtworkCrop crop);

  Future<void> delete(ArtworkCropTarget target, String targetId);
}
