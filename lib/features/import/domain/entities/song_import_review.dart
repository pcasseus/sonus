import '../models/resolved_metadata.dart';

enum ImportReviewReason {
  fallbackMetadata,
  unknownArtist,
  unknownAlbum,
  missingTrackNumber,
  missingDuration,
  looseFolder,
  ambiguousArtistCredit,

  /// Same artist, title and album as an existing song, but the duration or
  /// featured artists show a different recording. Imported as its own song;
  /// the user confirms or merges it.
  alternateRecording,
}

class ImportReviewPayload {
  const ImportReviewPayload({this.rawArtistCredit});

  final String? rawArtistCredit;

  bool get isEmpty {
    final value = rawArtistCredit?.trim();
    return value == null || value.isEmpty;
  }
}

class SongImportReview {
  static const Object _unset = Object();

  const SongImportReview({
    required this.songId,
    required this.metadataSource,
    required this.reasons,
    required this.createdAt,
    required this.updatedAt,
    this.payload,
    this.resolvedAt,
  });

  final String songId;
  final MetadataSource metadataSource;
  final List<ImportReviewReason> reasons;
  final ImportReviewPayload? payload;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isResolved => resolvedAt != null;

  bool get needsReview => !isResolved && reasons.isNotEmpty;

  SongImportReview copyWith({
    String? songId,
    MetadataSource? metadataSource,
    List<ImportReviewReason>? reasons,
    Object? payload = _unset,
    Object? resolvedAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SongImportReview(
      songId: songId ?? this.songId,
      metadataSource: metadataSource ?? this.metadataSource,
      reasons: reasons ?? this.reasons,
      payload: identical(payload, _unset)
          ? this.payload
          : payload as ImportReviewPayload?,
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
