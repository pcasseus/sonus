import '../../domain/entities/song_import_review.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';

typedef ImportReviewCleanupClock = DateTime Function();

class ImportReviewCleanupSummary {
  const ImportReviewCleanupSummary({
    required this.examined,
    required this.updated,
    required this.resolved,
    required this.skipped,
  });

  final int examined;
  final int updated;
  final int resolved;
  final int skipped;
}

class ImportReviewCleanupService {
  ImportReviewCleanupService({
    required SongImportReviewRepository reviewRepository,
    required SongRepository songRepository,
    ImportReviewCleanupClock? now,
  }) : this._(reviewRepository, songRepository, now ?? DateTime.now);

  const ImportReviewCleanupService._(
    this._reviewRepository,
    this._songRepository,
    this._now,
  );

  final SongImportReviewRepository _reviewRepository;
  final SongRepository _songRepository;
  final ImportReviewCleanupClock _now;

  Future<ImportReviewCleanupSummary> cleanupStaleDurationReasons({
    DateTime? now,
  }) async {
    final reviews = await _reviewRepository.getUnresolved();
    final timestamp = now ?? _now();

    var updated = 0;
    var resolved = 0;
    var skipped = 0;

    for (final review in reviews) {
      if (!review.reasons.contains(ImportReviewReason.missingDuration)) {
        skipped++;
        continue;
      }

      final song = await _songRepository.getById(review.songId);

      if (song == null || song.durationSeconds <= 0) {
        skipped++;
        continue;
      }

      final remainingReasons = review.reasons
          .where((reason) => reason != ImportReviewReason.missingDuration)
          .toList(growable: false);

      if (remainingReasons.isEmpty) {
        await _reviewRepository.save(
          review.copyWith(
            reasons: const [],
            resolvedAt: timestamp,
            updatedAt: timestamp,
          ),
        );
        resolved++;
      } else {
        await _reviewRepository.save(
          review.copyWith(
            reasons: List.unmodifiable(remainingReasons),
            updatedAt: timestamp,
          ),
        );
        updated++;
      }
    }

    return ImportReviewCleanupSummary(
      examined: reviews.length,
      updated: updated,
      resolved: resolved,
      skipped: skipped,
    );
  }
}
