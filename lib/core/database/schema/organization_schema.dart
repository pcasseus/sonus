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
  /// MusicBrainz release-group type (external) or the user (manual).
  ///
  /// Two independent facts share the album's row:
  /// - `kind`: a secondary classification (soundtrack, cast recording,
  ///   compilation). Null means unclassified.
  /// - `format` (SN-45): Single, EP or Album. Null means not stated, which
  ///   counts as an Album; it is never inferred from track counts.
  /// - `live` (SN-49): 1 for a live recording, 0 for the user's "not
  ///   live". Null means not stated.
  ///
  /// Each has its own authority, so a manual choice of one never hides the
  /// other. A row exists only while at least one of them is set.
  static Future<void> createAlbumReleaseClassifications(
    DatabaseExecutor db, {
    String table = DatabaseTables.albumReleaseClassifications,
  }) async {
    await db.execute('''
      CREATE TABLE $table (
        album_id TEXT PRIMARY KEY NOT NULL
          REFERENCES ${DatabaseTables.albums}(id)
          ON UPDATE CASCADE ON DELETE CASCADE,
        kind TEXT
          CHECK (
            kind IS NULL OR
            kind IN ('soundtrack', 'castRecording', 'compilation')
          ),
        authority TEXT
          CHECK (authority IS NULL OR authority IN ('external', 'manual')),
        source_reference TEXT,
        format TEXT
          CHECK (format IS NULL OR format IN ('single', 'ep', 'album')),
        format_authority TEXT
          CHECK (
            format_authority IS NULL OR
            format_authority IN ('external', 'manual')
          ),
        format_source_reference TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        live INTEGER CHECK (live IS NULL OR live IN (0, 1)),
        live_authority TEXT
          CHECK (
            live_authority IS NULL OR
            live_authority IN ('external', 'manual')
          ),
        live_source_reference TEXT,
        CHECK ((kind IS NULL) = (authority IS NULL)),
        CHECK ((format IS NULL) = (format_authority IS NULL)),
        CHECK ((live IS NULL) = (live_authority IS NULL)),
        CHECK (kind IS NOT NULL OR format IS NOT NULL OR live IS NOT NULL)
      )
    ''');
  }

  /// SN-49: adds Live beside the classification and the format. Every
  /// existing row is copied unchanged.
  static Future<void> addLiveClassification(DatabaseExecutor db) async {
    const table = DatabaseTables.albumReleaseClassifications;
    const staging = '${table}_rebuild';
    const copied =
        'album_id, kind, authority, source_reference, format, '
        'format_authority, format_source_reference, created_at, updated_at';

    final existing = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
    if (existing.single['count'] == 0) {
      // Nothing to copy: replace the empty table directly.
      await db.execute('DROP TABLE $table');
      await createAlbumReleaseClassifications(db);
      return;
    }

    await createAlbumReleaseClassifications(db, table: staging);
    await db.execute(
      'INSERT INTO $staging ($copied) SELECT $copied FROM $table',
    );
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE $staging RENAME TO $table');
  }

  /// SN-45: adds the release format beside the classification. Every
  /// existing row is copied unchanged.
  static Future<void> addReleaseFormats(DatabaseExecutor db) async {
    const table = DatabaseTables.albumReleaseClassifications;
    const staging = '${table}_rebuild';

    final existing = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
    if (existing.single['count'] == 0) {
      // Nothing to copy: replace the empty table directly.
      await db.execute('DROP TABLE $table');
      await createAlbumReleaseClassifications(db);
      return;
    }

    await createAlbumReleaseClassifications(db, table: staging);
    await db.execute('''
      INSERT INTO $staging (
        album_id, kind, authority, source_reference, created_at, updated_at
      )
      SELECT album_id, kind, authority, source_reference, created_at,
        updated_at
      FROM $table
    ''');
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE $staging RENAME TO $table');
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
