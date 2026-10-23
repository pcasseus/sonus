import '../../../../core/database/app_database.dart';
import '../../domain/models/track_lyrics.dart';
import '../../domain/repositories/track_lyrics_repository.dart';
import '../daos/track_lyrics_dao.dart';

class SqliteTrackLyricsRepository implements TrackLyricsRepository {
  const SqliteTrackLyricsRepository(this.dao, {this.appDatabase});

  final TrackLyricsDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit for read-only use or when a caller already owns the transaction.
  final AppDatabase? appDatabase;

  @override
  Future<TrackLyrics?> getBySongId(String songId) {
    return dao.findBySongId(songId);
  }

  @override
  Future<void> save({
    required String songId,
    String? plainText,
    String? syncedText,
  }) {
    final now = DateTime.now().toUtc();

    Future<void> upsert(TrackLyricsDao target) {
      return target.upsert(
        songId: songId,
        plainText: plainText,
        syncedText: syncedText,
        createdAt: now,
        updatedAt: now,
      );
    }

    final database = appDatabase;
    if (database == null) {
      return upsert(dao);
    }

    return database.transaction(
      (transaction) => upsert(TrackLyricsDao(transaction)),
    );
  }

  @override
  Future<void> deleteBySongId(String songId) {
    final database = appDatabase;
    if (database == null) {
      return dao.deleteBySongId(songId);
    }

    return database.transaction(
      (transaction) => TrackLyricsDao(transaction).deleteBySongId(songId),
    );
  }
}
