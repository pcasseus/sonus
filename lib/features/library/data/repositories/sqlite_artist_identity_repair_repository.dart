import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/repositories/artist_identity_repair_repository.dart';

class SqliteArtistIdentityRepairRepository
    implements ArtistIdentityRepairRepository {
  const SqliteArtistIdentityRepairRepository(this.db);

  final DatabaseExecutor db;

  @override
  Future<void> remapHistoricalArtistReferences({
    required String sourceArtistId,
    required String targetArtistId,
    required String targetArtistName,
  }) async {
    await db.update(
      DatabaseTables.playbackSessions,
      <String, Object?>{
        'artist_id': targetArtistId,
        'artist_name': targetArtistName,
      },
      where: 'artist_id = ?',
      whereArgs: <Object?>[sourceArtistId],
    );

    await db.update(
      DatabaseTables.qualifiedPlays,
      <String, Object?>{'artist_id': targetArtistId},
      where: 'artist_id = ?',
      whereArgs: <Object?>[sourceArtistId],
    );

    await db.update(
      DatabaseTables.chartEntries,
      <String, Object?>{
        'artist_id': targetArtistId,
        'artist_name': targetArtistName,
      },
      where: 'artist_id = ?',
      whereArgs: <Object?>[sourceArtistId],
    );

    await db.update(
      DatabaseTables.chartMomentEvents,
      <String, Object?>{
        'entity_artist_id': targetArtistId,
        'entity_artist_name': targetArtistName,
      },
      where: 'entity_artist_id = ?',
      whereArgs: <Object?>[sourceArtistId],
    );

    await db.update(
      DatabaseTables.chartMomentEvents,
      <String, Object?>{
        'related_entity_artist_id': targetArtistId,
        'related_entity_artist_name': targetArtistName,
      },
      where: 'related_entity_artist_id = ?',
      whereArgs: <Object?>[sourceArtistId],
    );
  }
}
