import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/song_artist_credit.dart';
import '../mappers/song_artist_credit_row_mapper.dart';

class SongArtistCreditDao {
  const SongArtistCreditDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(SongArtistCredit credit) async {
    await db.insert(
      DatabaseTables.songArtistCredits,
      SongArtistCreditRowMapper.toRow(credit),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(SongArtistCredit credit) async {
    final count = await db.update(
      DatabaseTables.songArtistCredits,
      SongArtistCreditRowMapper.toRow(credit),
      where: 'id = ?',
      whereArgs: [credit.id],
    );

    if (count != 1) {
      throw StateError('Song artist credit not found: ${credit.id}');
    }
  }

  Future<void> delete(String id) async {
    await db.delete(
      DatabaseTables.songArtistCredits,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<SongArtistCredit?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return SongArtistCreditRowMapper.fromRow(rows.single);
  }

  Future<List<SongArtistCredit>> findBySongId(String songId) async {
    final rows = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'song_id = ?',
      whereArgs: [songId],
      orderBy: 'position ASC, id ASC',
    );

    return rows.map(SongArtistCreditRowMapper.fromRow).toList(growable: false);
  }

  Future<List<SongArtistCredit>> findByArtistId(String artistId) async {
    final rows = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'artist_id = ?',
      whereArgs: [artistId],
      orderBy: 'updated_at DESC, id ASC',
    );

    return rows.map(SongArtistCreditRowMapper.fromRow).toList(growable: false);
  }

  Future<List<SongArtistCredit>> findUnlinkedByCanonicalName(
    String canonicalName,
  ) async {
    final rows = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'artist_id IS NULL AND canonical_credited_name = ?',
      whereArgs: [canonicalName],
      orderBy: 'updated_at ASC, id ASC',
    );

    return rows.map(SongArtistCreditRowMapper.fromRow).toList(growable: false);
  }
}
