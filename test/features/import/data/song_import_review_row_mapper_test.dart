import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/data/mappers/song_import_review_row_mapper.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';

void main() {
  test('song import review mapper round-trips every persisted field', () {
    final createdAt = DateTime.utc(2026, 9, 17, 12);
    final updatedAt = DateTime.utc(2026, 9, 17, 13);
    final resolvedAt = DateTime.utc(2026, 9, 17, 14);

    final review = SongImportReview(
      songId: 'song_review_mapper',
      metadataSource: MetadataSource.fallback,
      reasons: const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.unknownArtist,
        ImportReviewReason.missingDuration,
      ],
      resolvedAt: resolvedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = SongImportReviewRowMapper.toRow(review);
    final restored = SongImportReviewRowMapper.fromRow(row);

    expect(restored.songId, review.songId);
    expect(restored.metadataSource, MetadataSource.fallback);
    expect(restored.reasons, const [
      ImportReviewReason.fallbackMetadata,
      ImportReviewReason.unknownArtist,
      ImportReviewReason.missingDuration,
    ]);
    expect(restored.resolvedAt, resolvedAt);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
    expect(restored.isResolved, isTrue);
    expect(restored.needsReview, isFalse);
  });

  test('mapper preserves unresolved review state', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    final restored = SongImportReviewRowMapper.fromRow({
      'song_id': 'song_unresolved',
      'metadata_source': 'embedded',
      'review_reasons': '["missingTrackNumber"]',
      'resolved_at': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    expect(restored.metadataSource, MetadataSource.embedded);
    expect(restored.reasons, const [ImportReviewReason.missingTrackNumber]);
    expect(restored.resolvedAt, isNull);
    expect(restored.isResolved, isFalse);
    expect(restored.needsReview, isTrue);
  });

  test('mapper rejects review reasons that are not encoded as a list', () {
    final now = DateTime.utc(2026, 9, 17, 12).toIso8601String();

    expect(
      () => SongImportReviewRowMapper.fromRow({
        'song_id': 'song_invalid_reasons',
        'metadata_source': 'fallback',
        'review_reasons': '{"reason":"fallbackMetadata"}',
        'resolved_at': null,
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
