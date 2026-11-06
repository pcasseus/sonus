import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/repositories/artist_reference_repository.dart';

/// Answers [ArtistReferenceRepository] with EXISTS queries, and
/// [ArtistReferenceSummaryRepository] with one grouped count per table for
/// every artist at once. Reads only; never changes a row.
class SqliteArtistReferenceRepository
    implements ArtistReferenceRepository, ArtistReferenceSummaryRepository {
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

  @override
  Future<List<ArtistReferenceSummary>> summarizeAll() async {
    Future<Map<String, int>> countBy(String table, String column) => _counts('''
          SELECT $column AS artist_id, COUNT(*) AS n
          FROM $table
          WHERE $column IS NOT NULL
          GROUP BY $column
        ''');

    final albums = await countBy(DatabaseTables.albums, 'artist_id');
    final songs = await countBy(DatabaseTables.songs, 'artist_id');
    final credits = await countBy(
      DatabaseTables.songArtistCredits,
      'artist_id',
    );
    final assignments = await countBy(
      DatabaseTables.artistProjectAssignments,
      'artist_id',
    );
    final sessions = await countBy(
      DatabaseTables.playbackSessions,
      'artist_id',
    );
    final plays = await countBy(DatabaseTables.qualifiedPlays, 'artist_id');
    final chartEntries = await countBy(
      DatabaseTables.chartEntries,
      'artist_id',
    );
    final chartWeeks = await _counts('''
      SELECT ce.artist_id AS artist_id,
        COUNT(DISTINCT COALESCE(cs.week_start_utc, ce.chart_snapshot_id)) AS n
      FROM ${DatabaseTables.chartEntries} ce
      LEFT JOIN ${DatabaseTables.chartSnapshots} cs
        ON cs.id = ce.chart_snapshot_id
      WHERE ce.artist_id IS NOT NULL
      GROUP BY ce.artist_id
    ''');
    // A Moment naming the artist twice is still one Moment.
    final moments = await _counts('''
      SELECT artist_id, COUNT(DISTINCT id) AS n
      FROM (
        SELECT id, entity_artist_id AS artist_id
        FROM ${DatabaseTables.chartMomentEvents}
        UNION ALL
        SELECT id, related_entity_artist_id AS artist_id
        FROM ${DatabaseTables.chartMomentEvents}
      )
      WHERE artist_id IS NOT NULL
      GROUP BY artist_id
    ''');
    final pending = await _counts('''
      SELECT artist_id, COUNT(*) AS n
      FROM (
        SELECT artist_id FROM ${SyncSchema.artistWriteJournalTable}
        UNION ALL
        SELECT artist_id FROM ${SyncSchema.artistDependencyJournalTable}
      )
      WHERE artist_id IS NOT NULL
      GROUP BY artist_id
    ''');

    final artists = await _db.rawQuery('''
      SELECT id, name FROM ${DatabaseTables.artists}
      ORDER BY name COLLATE NOCASE ASC, id ASC
    ''');

    return [
      for (final row in artists)
        if (row['id'] case final String id)
          ArtistReferenceSummary(
            artistId: id,
            name: row['name'] as String? ?? '',
            songs: songs[id] ?? 0,
            albums: albums[id] ?? 0,
            credits: credits[id] ?? 0,
            projectAssignments: assignments[id] ?? 0,
            listeningSessions: sessions[id] ?? 0,
            qualifiedPlays: plays[id] ?? 0,
            chartEntries: chartEntries[id] ?? 0,
            chartWeeks: chartWeeks[id] ?? 0,
            moments: moments[id] ?? 0,
            pendingCloudWrites: pending[id] ?? 0,
          ),
    ];
  }

  @override
  Future<Set<String>> findRetiredArtistIds() async {
    String anyOf(Set<ArtistReference> kinds) => [
      for (final kind in kinds)
        for (final (table, column) in _sources[kind]!)
          'EXISTS(SELECT 1 FROM $table WHERE $column = ar.id)',
    ].join(' OR ');

    final rows = await _db.rawQuery('''
      SELECT ar.id AS id
      FROM ${DatabaseTables.artists} ar
      WHERE NOT (${anyOf(artistLibraryReferences)})
        AND (${anyOf(artistHistoryReferences)})
    ''');

    return {
      for (final row in rows)
        if (row['id'] case final String id) id,
    };
  }

  Future<Map<String, int>> _counts(String sql) async {
    final rows = await _db.rawQuery(sql);
    return {
      for (final row in rows)
        if (row['artist_id'] case final String id) id: row['n'] as int? ?? 0,
    };
  }
}
