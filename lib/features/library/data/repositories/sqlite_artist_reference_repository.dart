import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/repositories/artist_reference_repository.dart';

/// Answers [ArtistReferenceRepository] with EXISTS queries. Reads only;
/// never changes a row.
class SqliteArtistReferenceRepository implements ArtistReferenceRepository {
  const SqliteArtistReferenceRepository(this._db);

  final DatabaseExecutor _db;

  /// Each reference kind and the (table, column) pairs that hold it.
  static const Map<ArtistReference, List<(String, String)>> _sources = {
    ArtistReference.albums: [(DatabaseTables.albums, 'artist_id')],
    ArtistReference.songs: [(DatabaseTables.songs, 'artist_id')],
    ArtistReference.credits: [(DatabaseTables.songArtistCredits, 'artist_id')],
    ArtistReference.projectAssignment: [
      (DatabaseTables.artistProjectAssignments, 'artist_id'),
    ],
    ArtistReference.listeningHistory: [
      (DatabaseTables.playbackSessions, 'artist_id'),
      (DatabaseTables.qualifiedPlays, 'artist_id'),
    ],
    ArtistReference.charts: [(DatabaseTables.chartEntries, 'artist_id')],
    ArtistReference.moments: [
      (DatabaseTables.chartMomentEvents, 'entity_artist_id'),
      (DatabaseTables.chartMomentEvents, 'related_entity_artist_id'),
    ],
    ArtistReference.pendingCloudWrite: [
      (SyncSchema.artistWriteJournalTable, 'artist_id'),
      (SyncSchema.artistDependencyJournalTable, 'artist_id'),
    ],
  };

  @override
  Future<Set<ArtistReference>> findReferences(String artistId) async {
    final found = <ArtistReference>{};

    for (final MapEntry(key: kind, value: sources) in _sources.entries) {
      for (final (table, column) in sources) {
        if (await _exists(table, column, artistId)) {
          found.add(kind);
          break;
        }
      }
    }

    return found;
  }

  Future<bool> _exists(String table, String column, String artistId) async {
    final rows = await _db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM $table WHERE $column = ?) AS found',
      [artistId],
    );
    return (rows.single['found'] as int? ?? 0) == 1;
  }
}
