import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/artwork_asset.dart';
import '../mappers/artwork_asset_row_mapper.dart';

class ArtworkAssetDao {
  const ArtworkAssetDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(ArtworkAsset artworkAsset) async {
    await db.insert(
      DatabaseTables.artworkAssets,
      ArtworkAssetRowMapper.toRow(artworkAsset),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(ArtworkAsset artworkAsset) async {
    final count = await db.update(
      DatabaseTables.artworkAssets,
      ArtworkAssetRowMapper.toRow(artworkAsset),
      where: 'id = ?',
      whereArgs: [artworkAsset.id],
    );

    if (count != 1) {
      throw StateError('Artwork asset not found: ${artworkAsset.id}');
    }
  }

  Future<ArtworkAsset?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.artworkAssets,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ArtworkAssetRowMapper.fromRow(rows.single);
  }

  Future<ArtworkAsset?> findByNormalizedPath(String normalizedPath) async {
    final rows = await db.query(
      DatabaseTables.artworkAssets,
      where: 'normalized_path = ?',
      whereArgs: [normalizedPath],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ArtworkAssetRowMapper.fromRow(rows.single);
  }

  Future<List<ArtworkAsset>> findAll() async {
    final rows = await db.query(
      DatabaseTables.artworkAssets,
      orderBy: 'created_at DESC, id ASC',
    );

    return rows.map(ArtworkAssetRowMapper.fromRow).toList(growable: false);
  }
}
