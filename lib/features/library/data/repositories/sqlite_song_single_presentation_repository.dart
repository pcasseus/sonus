import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../domain/entities/song_single_presentation.dart';
import '../../domain/repositories/song_single_presentation_repository.dart';

class SqliteSongSinglePresentationRepository
    implements SongSinglePresentationRepository {
  const SqliteSongSinglePresentationRepository(this.db, {this.appDatabase});

  final DatabaseExecutor db;

  /// Coordinates writes with an exclusive restore (restore admission).
  /// Omit only when the caller already owns the transaction.
  final AppDatabase? appDatabase;

  static const _table = DatabaseTables.songSinglePresentations;

  static const _select =
      '''
    SELECT p.song_id, p.release_date, p.release_date_precision,
           p.artwork_id, a.file_path AS artwork_path,
           p.use_artwork_in_charts, p.created_at, p.updated_at
    FROM $_table p
    LEFT JOIN ${DatabaseTables.artworkAssets} a ON a.id = p.artwork_id
  ''';

  @override
  Future<SongSinglePresentation?> getBySongId(String songId) async {
    final rows = await db.rawQuery('$_select WHERE p.song_id = ?', [songId]);
    return rows.isEmpty ? null : _read(rows.single);
  }

  @override
  Future<Map<String, SongSinglePresentation>> getAll() async {
    final rows = await db.rawQuery(_select);
    return {for (final row in rows) row['song_id']! as String: _read(row)};
  }

  @override
  Future<void> save(SongSinglePresentation presentation) {
    if (presentation.isEmpty) return clear(presentation.songId);
    final date = SongSinglePresentation.encodeDate(presentation.releaseDate);
    final values = {
      'song_id': presentation.songId,
      'release_date': date?.$1,
      'release_date_precision': date?.$2,
      'artwork_id': presentation.artworkId,
      'use_artwork_in_charts': presentation.useArtworkInCharts ? 1 : 0,
      'created_at': presentation.createdAt.toUtc().toIso8601String(),
      'updated_at': presentation.updatedAt.toUtc().toIso8601String(),
    };
    return _write(
      (target) => target.insert(
        _table,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      ),
    );
  }

  @override
  Future<void> clear(String songId) => _write(
    (target) =>
        target.delete(_table, where: 'song_id = ?', whereArgs: [songId]),
  );

  Future<void> _write(Future<Object?> Function(DatabaseExecutor) write) async {
    final database = appDatabase;
    if (database == null) {
      await write(db);
      return;
    }
    await database.transaction((transaction) => write(transaction));
  }

  static SongSinglePresentation _read(Map<String, Object?> row) =>
      SongSinglePresentation(
        songId: row['song_id']! as String,
        releaseDate: SongSinglePresentation.decodeDate(
          row['release_date'] as String?,
          row['release_date_precision'] as String?,
        ),
        artworkId: row['artwork_id'] as String?,
        artworkPath: row['artwork_path'] as String?,
        useArtworkInCharts: row['use_artwork_in_charts'] == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
