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
    this.sourceId,
    this.lastSeenAt,
    this.fileSizeBytes,
    this.modifiedAt,
    this.audioSignature,
    this.audioFullHash,
    this.signatureVersion,
  });

  final String id;
  final String songId;
  final String filePath;
  final String normalizedPath;
  final String? sourceId;
  final bool isAvailable;
  final DateTime? lastSeenAt;
  final int? fileSizeBytes;
  final DateTime? modifiedAt;

  /// The sampled audio identity, read from the file's bytes (BUG-09); null
  /// until read, or when the audio could not be read with confidence.
  final String? audioSignature;

  /// SHA-256 of all of the file's audio bytes: the proof needed before the
  /// file is rebound automatically.
  final String? audioFullHash;

  /// The rules that produced [audioSignature] and [audioFullHash].
  final int? signatureVersion;

  final DateTime createdAt;
  final DateTime updatedAt;

  MediaFileBinding copyWith({
    String? id,
    String? songId,
    String? filePath,
    String? normalizedPath,
    Object? sourceId = _unset,
    bool? isAvailable,
    Object? lastSeenAt = _unset,
    Object? fileSizeBytes = _unset,
    Object? modifiedAt = _unset,
    Object? audioSignature = _unset,
    Object? audioFullHash = _unset,
    Object? signatureVersion = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MediaFileBinding(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      filePath: filePath ?? this.filePath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      sourceId: identical(sourceId, _unset)
          ? this.sourceId
          : sourceId as String?,
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
      audioSignature: identical(audioSignature, _unset)
          ? this.audioSignature
          : audioSignature as String?,
      audioFullHash: identical(audioFullHash, _unset)
          ? this.audioFullHash
          : audioFullHash as String?,
      signatureVersion: identical(signatureVersion, _unset)
          ? this.signatureVersion
          : signatureVersion as int?,
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
