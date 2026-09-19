import '../models/resolved_metadata.dart';

enum ImportReviewReason {
  fallbackMetadata,
  unknownArtist,
  unknownAlbum,
  missingTrackNumber,
  missingDuration,
  looseFolder,
}

class SongImportReview {
  static const Object _unset = Object();

  const SongImportReview({
    required this.songId,
    required this.metadataSource,
    required this.reasons,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  final String songId;
  final MetadataSource metadataSource;
  final List<ImportReviewReason> reasons;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isResolved => resolvedAt != null;

  bool get needsReview => !isResolved && reasons.isNotEmpty;

  SongImportReview copyWith({
    String? songId,
    MetadataSource? metadataSource,
    List<ImportReviewReason>? reasons,
    Object? resolvedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SongImportReview(
      songId: songId ?? this.songId,
      metadataSource: metadataSource ?? this.metadataSource,
      reasons: reasons ?? this.reasons,
      resolvedAt: identical(resolvedAt, _unset)
          ? this.resolvedAt
          : resolvedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SongImportReview && other.songId == songId;
  }

  @override
  int get hashCode => songId.hashCode;
}
