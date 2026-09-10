class MediaFileBinding {
  static const Object _unset = Object();

  const MediaFileBinding({
    required this.id,
    required this.songId,
    required this.filePath,
    required this.normalizedPath,
    required this.isAvailable,
    required this.createdAt,
    required this.updatedAt,
    this.lastSeenAt,
    this.fileSizeBytes,
    this.modifiedAt,
  });

  final String id;
  final String songId;
  final String filePath;
  final String normalizedPath;
  final bool isAvailable;
  final DateTime? lastSeenAt;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  MediaFileBinding copyWith({
    String? id,
    String? songId,
    String? filePath,
    String? normalizedPath,
    bool? isAvailable,
    Object? lastSeenAt = _unset,
    Object? fileSizeBytes = _unset,
    Object? modifiedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MediaFileBinding(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      filePath: filePath ?? this.filePath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      isAvailable: isAvailable ?? this.isAvailable,
      lastSeenAt: identical(lastSeenAt, _unset)
          ? this.lastSeenAt
          : lastSeenAt as DateTime?,
      fileSizeBytes: identical(fileSizeBytes, _unset)
          ? this.fileSizeBytes
          : fileSizeBytes as int?,
      modifiedAt: identical(modifiedAt, _unset)
          ? this.modifiedAt
          : modifiedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MediaFileBinding && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
