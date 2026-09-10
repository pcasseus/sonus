import 'package:sonus_next/core/identity/entity_id.dart';
import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';

abstract final class MediaFileBindingFactory {
  static MediaFileBinding create({
    required String songId,
    required String filePath,
    bool isAvailable = true,
    DateTime? lastSeenAt,
    int? fileSizeBytes,
    DateTime? modifiedAt,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    return MediaFileBinding(
      id: EntityId.mediaFileBinding(),
      songId: songId,
      filePath: filePath.trim(),
      normalizedPath: TextNormalizer.normalizePath(filePath),
      isAvailable: isAvailable,
      lastSeenAt: lastSeenAt ?? timestamp,
      fileSizeBytes: fileSizeBytes,
      modifiedAt: modifiedAt,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}
