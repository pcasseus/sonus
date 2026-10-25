import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

/// Read-only checks of the persisted library. Each returns the ids it
/// found; none writes anything.
class LibraryIntegrityDao {
  const LibraryIntegrityDao(this.db);

  final DatabaseExecutor db;

  Future<List<String>> _ids(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    return [for (final row in rows) row.values.first! as String];
  }

  Future<int> _count(String sql) async =>
      Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;

  Future<({int songs, int albums, int artists})> totals() async => (
    songs: await _count('SELECT COUNT(*) FROM ${DatabaseTables.songs}'),
    albums: await _count('SELECT COUNT(*) FROM ${DatabaseTables.albums}'),
    artists: await _count('SELECT COUNT(*) FROM ${DatabaseTables.artists}'),
  );

  /// Songs with no available audio file.
  Future<List<String>> songsWithoutPlayableFile() => _ids('''
    SELECT s.id FROM ${DatabaseTables.songs} s
    WHERE NOT EXISTS (
      SELECT 1 FROM ${DatabaseTables.mediaFileBindings} b
      WHERE b.song_id = s.id AND b.is_available = 1
    )
    ORDER BY s.id
  ''');

  /// Pairs of songs on one album that look like the same recording: same
  /// artist, title and version, durations within three seconds. Returned
  /// as "first|second".
  Future<List<String>> possibleDuplicateRecordings() => _ids('''
    SELECT a.id || '|' || b.id FROM ${DatabaseTables.songs} a
    INNER JOIN ${DatabaseTables.songs} b
      ON b.album_id = a.album_id
      AND b.artist_id = a.artist_id
      AND b.canonical_title = a.canonical_title
      AND COALESCE(b.version_label, '') = COALESCE(a.version_label, '')
      AND a.id < b.id
    WHERE a.duration_seconds > 0 AND b.duration_seconds > 0
      AND ABS(a.duration_seconds - b.duration_seconds) <= 3
    ORDER BY a.id, b.id
  ''');

  Future<List<String>> albumsWithoutEditions() => _ids('''
    SELECT al.id FROM ${DatabaseTables.albums} al
    WHERE NOT EXISTS (
      SELECT 1 FROM ${DatabaseTables.albumEditions} e WHERE e.album_id = al.id
    )
    ORDER BY al.id
  ''');

  /// Albums with editions but no primary edition, with their edition count.
  /// Returned as "albumId|editionCount|onlyEditionId".
  Future<List<String>> albumsWithoutPrimaryEdition() => _ids('''
    SELECT al.id || '|' || COUNT(e.id) || '|' || MIN(e.id)
    FROM ${DatabaseTables.albums} al
    INNER JOIN ${DatabaseTables.albumEditions} e ON e.album_id = al.id
    GROUP BY al.id
    HAVING SUM(e.is_primary) = 0
    ORDER BY al.id
  ''');

  Future<List<String>> albumsWithSeveralPrimaryEditions() => _ids('''
    SELECT e.album_id FROM ${DatabaseTables.albumEditions} e
    GROUP BY e.album_id
    HAVING SUM(e.is_primary) > 1
    ORDER BY e.album_id
  ''');

  /// Songs their own home edition doesn't list. Returned as
  /// "songId|editionId".
  Future<List<String>> songsMissingFromHomeEdition() => _ids('''
    SELECT s.id || '|' || s.album_edition_id FROM ${DatabaseTables.songs} s
    WHERE NOT EXISTS (
      SELECT 1 FROM ${DatabaseTables.albumEditionTracks} m
      WHERE m.song_id = s.id AND m.album_edition_id = s.album_edition_id
    )
    ORDER BY s.id
  ''');

  /// Listings of a song on an edition of another album.
  Future<List<String>> listingsOnAnotherAlbum() => _ids('''
    SELECT m.song_id || '|' || m.album_edition_id
    FROM ${DatabaseTables.albumEditionTracks} m
    INNER JOIN ${DatabaseTables.albumEditions} e ON e.id = m.album_edition_id
    INNER JOIN ${DatabaseTables.songs} s ON s.id = m.song_id
    WHERE e.album_id <> s.album_id
    ORDER BY m.song_id
  ''');

  /// Editions where two tracks share a disc and track number.
  Future<List<String>> editionsWithRepeatedPositions() => _ids('''
    SELECT DISTINCT m.album_edition_id FROM ${DatabaseTables.albumEditionTracks} m
    WHERE m.track_number > 0
    GROUP BY m.album_edition_id, m.disc_number, m.track_number
    HAVING COUNT(*) > 1
    ORDER BY m.album_edition_id
  ''');

  Future<List<String>> listingsWithoutTrackNumber() => _ids('''
    SELECT m.song_id FROM ${DatabaseTables.albumEditionTracks} m
    WHERE m.track_number <= 0
    ORDER BY m.song_id
  ''');

  /// Songs with structured credits but no main (primary or co-primary) one.
  Future<List<String>> songsWithoutMainCredit() => _ids('''
    SELECT s.id FROM ${DatabaseTables.songs} s
    WHERE EXISTS (
      SELECT 1 FROM ${DatabaseTables.songArtistCredits} c WHERE c.song_id = s.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM ${DatabaseTables.songArtistCredits} c
      WHERE c.song_id = s.id AND c.role IN ('primary', 'coPrimary')
    )
    ORDER BY s.id
  ''');

  /// Credited names not linked to any artist (e.g. featured performers).
  Future<List<String>> unlinkedCredits() => _ids('''
    SELECT c.id FROM ${DatabaseTables.songArtistCredits} c
    WHERE c.artist_id IS NULL
    ORDER BY c.id
  ''');

  Future<List<({String id, String path})>> artworkFiles() async {
    final rows = await db.query(
      DatabaseTables.artworkAssets,
      columns: ['id', 'file_path'],
      orderBy: 'id',
    );
    return [
      for (final row in rows)
        (id: row['id']! as String, path: row['file_path']! as String),
    ];
  }

  Future<List<String>> songsWithoutDuration() => _ids('''
    SELECT id FROM ${DatabaseTables.songs} WHERE duration_seconds <= 0 ORDER BY id
  ''');

  /// Artists and albums named "Unknown Artist" or "Unknown Album".
  Future<List<String>> placeholderNames() => _ids('''
    SELECT id FROM ${DatabaseTables.artists} WHERE canonical_name = 'unknown artist'
    UNION ALL
    SELECT id FROM ${DatabaseTables.albums} WHERE canonical_title = 'unknown album'
  ''');

  Future<List<String>> unresolvedImportReviews() => _ids('''
    SELECT song_id FROM ${DatabaseTables.songImportReviews}
    WHERE resolved_at IS NULL
    ORDER BY song_id
  ''');

  /// Metadata fields the user set or confirmed.
  Future<int> userConfirmedFields() => _count('''
    SELECT COUNT(*) FROM ${DatabaseTables.metadataFieldStates}
    WHERE authority IN ('manual', 'confirmed')
  ''');

  Future<int> classifiedProjects() => _count(
    'SELECT COUNT(*) FROM ${DatabaseTables.albumReleaseClassifications}',
  );
}
