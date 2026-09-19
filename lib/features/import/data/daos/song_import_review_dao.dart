import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/song_import_review.dart';
import '../mappers/song_import_review_row_mapper.dart';

class SongImportReviewDao {
  const SongImportReviewDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(SongImportReview review) async {
    await db.insert(
      DatabaseTables.songImportReviews,
      SongImportReviewRowMapper.toRow(review),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(SongImportReview review) async {
    final count = await db.update(
      DatabaseTables.songImportReviews,
      SongImportReviewRowMapper.toRow(review),
      where: 'song_id = ?',
      whereArgs: [review.songId],
    );

    if (count != 1) {
      throw StateError('Song import review not found: ${review.songId}');
    }
  }

  Future<SongImportReview?> findBySongId(String songId) async {
    final rows = await db.query(
      DatabaseTables.songImportReviews,
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return SongImportReviewRowMapper.fromRow(rows.single);
  }

  Future<List<SongImportReview>> findUnresolved() async {
    final rows = await db.query(
      DatabaseTables.songImportReviews,
      where: 'resolved_at IS NULL',
      orderBy: 'created_at ASC, song_id ASC',
    );

    return rows
        .map(SongImportReviewRowMapper.fromRow)
        .toList(growable: false);
  }

  Future<int> countUnresolved() async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS review_count
      FROM ${DatabaseTables.songImportReviews}
      WHERE resolved_at IS NULL
      ''',
    );

    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
