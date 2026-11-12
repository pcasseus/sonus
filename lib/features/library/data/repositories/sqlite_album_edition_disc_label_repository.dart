import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/album_edition_disc_label.dart';
import '../../domain/repositories/album_edition_disc_label_repository.dart';

class SqliteAlbumEditionDiscLabelRepository
    implements AlbumEditionDiscLabelRepository {
  const SqliteAlbumEditionDiscLabelRepository(this.db);

  final DatabaseExecutor db;

  static const _table = DatabaseTables.albumEditionDiscLabels;

  @override
  Future<List<AlbumEditionDiscLabel>> getByEditionId(String editionId) async {
    final rows = await db.query(
      _table,
      where: 'album_edition_id = ?',
      whereArgs: [editionId],
      orderBy: 'disc_number',
    );
    return [
      for (final row in rows)
        AlbumEditionDiscLabel(
          albumEditionId: row['album_edition_id']! as String,
          discNumber: row['disc_number']! as int,
          label: row['label']! as String,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
    ];
  }

  @override
  Future<void> save(AlbumEditionDiscLabel label) async {
    await db.insert(_table, {
      'album_edition_id': label.albumEditionId,
      'disc_number': label.discNumber,
      'label': label.label.trim(),
      'created_at': label.createdAt.toUtc().toIso8601String(),
      'updated_at': label.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete({
    required String editionId,
    required int discNumber,
  }) async {
    await db.delete(
      _table,
      where: 'album_edition_id = ? AND disc_number = ?',
      whereArgs: [editionId, discNumber],
    );
  }

  @override
  Future<void> keepOnly({
    required String editionId,
    required Set<int> discs,
  }) async {
    final kept = discs.toList(growable: false);
    await db.delete(
      _table,
      where: kept.isEmpty
          ? 'album_edition_id = ?'
          : 'album_edition_id = ? AND disc_number NOT IN '
                '(${List.filled(kept.length, '?').join(', ')})',
      whereArgs: [editionId, ...kept],
    );
  }
}
