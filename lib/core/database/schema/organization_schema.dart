import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// How the library is organized beyond the credits themselves: what kind of
/// release an album is, and where an artist is shown.
///
/// Both tables are device-local (not in backups, not synced). Their rows
/// cascade away with their album or artist, and survive restores, which
/// update albums and artists in place.
abstract final class OrganizationSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createAlbumReleaseClassifications(db);
    await createArtistProjectAssignments(db);
  }

  /// What kind of release an album is, only from real evidence: a
  /// MusicBrainz release-group type (external) or the user (manual). No row
  /// means unclassified; it is never inferred from titles or credit counts.
  static Future<void> createAlbumReleaseClassifications(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.albumReleaseClassifications} (
        album_id TEXT PRIMARY KEY NOT NULL
          REFERENCES ${DatabaseTables.albums}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        kind TEXT NOT NULL
          CHECK (kind IN ('soundtrack', 'castRecording', 'compilation')),
        authority TEXT NOT NULL
          CHECK (authority IN ('external', 'manual')),
        source_reference TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Where an artist appears in the Library. "grouped" shows the artist
  /// under a project's collaborators instead of as its own Library entry;
  /// "standalone" keeps an artist that would be grouped automatically as
  /// its own entry. No row means the automatic rule applies. Credits are
  /// never changed, and search and profiles are unaffected.
  static Future<void> createArtistProjectAssignments(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.artistProjectAssignments} (
        artist_id TEXT PRIMARY KEY NOT NULL
          REFERENCES ${DatabaseTables.artists}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        album_id TEXT
          REFERENCES ${DatabaseTables.albums}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        mode TEXT NOT NULL CHECK (mode IN ('grouped', 'standalone')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (mode = 'standalone' OR album_id IS NOT NULL)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_artist_project_assignments_album_id
      ON ${DatabaseTables.artistProjectAssignments}(album_id)
    ''');
  }
}
