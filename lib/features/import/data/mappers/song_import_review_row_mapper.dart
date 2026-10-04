import 'dart:convert';

import '../../domain/entities/song_import_review.dart';
import '../../domain/models/resolved_metadata.dart';

abstract final class SongImportReviewRowMapper {
  static Map<String, Object?> toRow(SongImportReview review) {
    return {
      'song_id': review.songId,
      'metadata_source': review.metadataSource.name,
      'review_reasons': jsonEncode(
        review.reasons.map((reason) => reason.name).toList(growable: false),
      ),
      'review_payload': _encodePayload(review.payload),
      'resolved_at': review.resolvedAt?.toUtc().toIso8601String(),
      'created_at': review.createdAt.toUtc().toIso8601String(),
      'updated_at': review.updatedAt.toUtc().toIso8601String(),
    };
  }

  static SongImportReview fromRow(Map<String, Object?> row) {
    final encodedReasons = row['review_reasons'] as String? ?? '[]';
    final decodedReasons = jsonDecode(encodedReasons);

    if (decodedReasons is! List) {
      throw const FormatException(
        'Import review reasons must be encoded as a JSON list.',
      );
    }

    return SongImportReview(
      songId: row['song_id'] as String,
      metadataSource: MetadataSource.values.byName(
        row['metadata_source'] as String,
      ),
      reasons: decodedReasons
          .map((value) => ImportReviewReason.values.byName(value as String))
          .toList(growable: false),
      payload: _decodePayload(row['review_payload'] as String?),
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.parse(row['resolved_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static String? _encodePayload(ImportReviewPayload? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }

    return jsonEncode({
      if (payload.rawArtistCredit != null)
        'rawArtistCredit': payload.rawArtistCredit,
    });
  }

  static ImportReviewPayload? _decodePayload(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(encoded);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Import review payload must be encoded as a JSON object.',
      );
    }

    final rawArtistCredit = decoded['rawArtistCredit'] as String?;

    final payload = ImportReviewPayload(rawArtistCredit: rawArtistCredit);

    return payload.isEmpty ? null : payload;
  }
}
