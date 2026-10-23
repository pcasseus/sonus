import '../../../../core/database/app_database.dart';
import '../../data/daos/song_import_review_dao.dart';
import '../../data/repositories/sqlite_song_import_review_repository.dart';
import '../../domain/entities/song_import_review.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
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

enum _CandidateOutcome { updated, resolved, skipped }

class ImportReviewCleanupService {
  ImportReviewCleanupService({
    required SongImportReviewRepository reviewRepository,
    required SongRepository songRepository,
    AppDatabase? appDatabase,
    ImportReviewCleanupClock? now,
  }) : this._(
         reviewRepository,
         songRepository,
         appDatabase,
         now ?? DateTime.now,
       );

  const ImportReviewCleanupService._(
    this._reviewRepository,
    this._songRepository,
    this._appDatabase,
    this._now,
  );

  final SongImportReviewRepository _reviewRepository;
  final SongRepository _songRepository;

  /// When set, each candidate is decided and written in its own short
  /// transaction that participates in restore admission.
  final AppDatabase? _appDatabase;
  final ImportReviewCleanupClock _now;

  /// The listing only nominates candidates. Each one is re-read before it is
  /// written, so a review resolved, edited, or removed after the listing
  /// (including by a restore) is never overwritten from the stale snapshot.
  /// A restore rejection stops the pass; the post-restore restart runs it
  /// again.
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

      switch (await _cleanupCandidate(review.songId, timestamp)) {
        case _CandidateOutcome.updated:
          updated++;
        case _CandidateOutcome.resolved:
          resolved++;
        case _CandidateOutcome.skipped:
          skipped++;
      }
    }

    return ImportReviewCleanupSummary(
      examined: reviews.length,
      updated: updated,
      resolved: resolved,
      skipped: skipped,
    );
  }

  Future<_CandidateOutcome> _cleanupCandidate(
    String songId,
    DateTime timestamp,
  ) {
    final database = _appDatabase;
    if (database == null) {
      return _cleanup(songId, timestamp, _reviewRepository, _songRepository);
    }

    // Repositories scoped to this transaction. The admission-wrapped review
    // repository must not be used here: it would open a nested transaction.
    return database.transaction(
      (transaction) => _cleanup(
        songId,
        timestamp,
        SqliteSongImportReviewRepository(SongImportReviewDao(transaction)),
        SqliteSongRepository(SongDao(transaction)),
      ),
    );
  }

  static Future<_CandidateOutcome> _cleanup(
    String songId,
    DateTime timestamp,
    SongImportReviewRepository reviews,
    SongRepository songs,
  ) async {
    final review = await reviews.getBySongId(songId);

    if (review == null ||
        review.isResolved ||
        !review.reasons.contains(ImportReviewReason.missingDuration)) {
      return _CandidateOutcome.skipped;
    }

    final song = await songs.getById(songId);

    if (song == null || song.durationSeconds <= 0) {
      return _CandidateOutcome.skipped;
    }

    final remainingReasons = review.reasons
        .where((reason) => reason != ImportReviewReason.missingDuration)
        .toList(growable: false);

    if (remainingReasons.isEmpty) {
      await reviews.save(
        review.copyWith(
          reasons: const [],
          resolvedAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      return _CandidateOutcome.resolved;
    }

    await reviews.save(
      review.copyWith(
        reasons: List.unmodifiable(remainingReasons),
        updatedAt: timestamp,
      ),
    );
    return _CandidateOutcome.updated;
  }
}
