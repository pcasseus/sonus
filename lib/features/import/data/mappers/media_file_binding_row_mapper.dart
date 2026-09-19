import '../../domain/entities/media_file_binding.dart';

abstract final class MediaFileBindingRowMapper {
  static Map<String, Object?> toRow(MediaFileBinding binding) {
    return {
      'id': binding.id,
      'song_id': binding.songId,
      'file_path': binding.filePath,
      'normalized_path': binding.normalizedPath,
      'source_id': binding.sourceId,
      'is_available': binding.isAvailable ? 1 : 0,
      'last_seen_at': binding.lastSeenAt?.toUtc().toIso8601String(),
      'file_size_bytes': binding.fileSizeBytes,
      'modified_at': binding.modifiedAt?.toUtc().toIso8601String(),
      'created_at': binding.createdAt.toUtc().toIso8601String(),
      'updated_at': binding.updatedAt.toUtc().toIso8601String(),
    };
  }

  static MediaFileBinding fromRow(Map<String, Object?> row) {
    return MediaFileBinding(
      id: row['id'] as String,
      songId: row['song_id'] as String,
      filePath: row['file_path'] as String,
      normalizedPath: row['normalized_path'] as String,
      sourceId: row['source_id'] as String?,
      isAvailable: (row['is_available'] as int? ?? 0) == 1,
      lastSeenAt: row['last_seen_at'] == null
          ? null
          : DateTime.parse(row['last_seen_at'] as String),
      fileSizeBytes: row['file_size_bytes'] as int?,
      modifiedAt: row['modified_at'] == null
          ? null
          : DateTime.parse(row['modified_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
