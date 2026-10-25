import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/artwork_crop.dart';
import '../../domain/repositories/artwork_crop_repository.dart';

class SqliteArtworkCropRepository implements ArtworkCropRepository {
  const SqliteArtworkCropRepository(this._database);

  final DatabaseExecutor _database;

  @override
  Future<ArtworkCrop?> get(ArtworkCropTarget target, String targetId) async {
    final rows = await _database.query(
      DatabaseTables.artworkCrops,
      where: 'target_type = ? AND target_id = ?',
      whereArgs: [target.name, targetId],
      limit: 1,
    );

    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> save(ArtworkCrop crop) {
    return _database.insert(DatabaseTables.artworkCrops, {
      'target_type': crop.target.name,
      'target_id': crop.targetId,
      'source_artwork_id': crop.sourceArtworkId,
      'output_artwork_id': crop.outputArtworkId,
      'crop_left': crop.rect.left,
      'crop_top': crop.rect.top,
      'crop_width': crop.rect.width,
      'crop_height': crop.rect.height,
      'created_at': crop.createdAt.toUtc().toIso8601String(),
      'updated_at': crop.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(ArtworkCropTarget target, String targetId) {
    return _database.delete(
      DatabaseTables.artworkCrops,
      where: 'target_type = ? AND target_id = ?',
      whereArgs: [target.name, targetId],
    );
  }

  static ArtworkCrop? _fromRow(Map<String, Object?> row) {
    final target = ArtworkCropTarget.values
        .where((value) => value.name == row['target_type'])
        .firstOrNull;

    if (target == null) {
      return null;
    }

    try {
      return ArtworkCrop(
        target: target,
        targetId: row['target_id']! as String,
        sourceArtworkId: row['source_artwork_id']! as String,
        outputArtworkId: row['output_artwork_id']! as String,
        rect: CropRect(
          left: (row['crop_left']! as num).toDouble(),
          top: (row['crop_top']! as num).toDouble(),
          width: (row['crop_width']! as num).toDouble(),
          height: (row['crop_height']! as num).toDouble(),
        ),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
    } on ArgumentError {
      // A stored rectangle that no longer validates is treated as no crop:
      // the assigned artwork still shows as it is.
      return null;
    }
  }
}
