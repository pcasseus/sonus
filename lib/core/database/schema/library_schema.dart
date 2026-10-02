import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class LibrarySchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createArtworkAssets(db);
    await _createArtists(db);
    await _createAlbums(db);
    await _createAlbumEditions(db);
    await _createSongs(db);
    await createAlbumEditionTracks(db);
    await createSongArtistCredits(db);
    await _createMediaFileBindings(db);
    await _createIndexes(db);
  }

  static Future<void> _createArtists(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE ${DatabaseTables.artists} (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      canonical_name TEXT NOT NULL,
      header_artwork_id TEXT,
      top_artists_artwork_id TEXT,
      is_blacklisted INTEGER NOT NULL DEFAULT 0
        CHECK (is_blacklisted IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,

      FOREIGN KEY (header_artwork_id)
        REFERENCES ${DatabaseTables.artworkAssets}(id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

      FOREIGN KEY (top_artists_artwork_id)
        REFERENCES ${DatabaseTables.artworkAssets}(id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
    )
  ''');
  }

  static Future<void> _createAlbums(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.albums} (
        id TEXT PRIMARY KEY NOT NULL,
        artist_id TEXT NOT NULL,
        title TEXT NOT NULL,
        canonical_title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (artist_id)
          REFERENCES ${DatabaseTables.artists}(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');
  }

  static Future<void> _createAlbumEditions(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE ${DatabaseTables.albumEditions} (
      id TEXT PRIMARY KEY NOT NULL,
      album_id TEXT NOT NULL,
      title TEXT NOT NULL,
      type TEXT NOT NULL,
      is_primary INTEGER NOT NULL DEFAULT 0
        CHECK (is_primary IN (0, 1)),
      release_date TEXT,
      genre TEXT,
      artwork_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,

      FOREIGN KEY (album_id)
        REFERENCES ${DatabaseTables.albums}(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

      FOREIGN KEY (artwork_id)
        REFERENCES ${DatabaseTables.artworkAssets}(id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
    )
  ''');
  }

  static Future<void> _createSongs(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE ${DatabaseTables.songs} (
      id TEXT PRIMARY KEY NOT NULL,
      artist_id TEXT NOT NULL,
      album_id TEXT NOT NULL,
      album_edition_id TEXT NOT NULL,
      title TEXT NOT NULL,
      canonical_title TEXT NOT NULL,
      track_number INTEGER NOT NULL DEFAULT 0
        CHECK (track_number >= 0),
      disc_number INTEGER NOT NULL DEFAULT 1
        CHECK (disc_number >= 0),
      duration_seconds INTEGER NOT NULL DEFAULT 0
        CHECK (duration_seconds >= 0),
      is_single INTEGER NOT NULL DEFAULT 0
        CHECK (is_single IN (0, 1)),
      is_blocked INTEGER NOT NULL DEFAULT 0
        CHECK (is_blocked IN (0, 1)),
      featured_artists TEXT NOT NULL DEFAULT '[]',
      artwork_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,

      FOREIGN KEY (artist_id)
        REFERENCES ${DatabaseTables.artists}(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

      FOREIGN KEY (album_id)
        REFERENCES ${DatabaseTables.albums}(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

      FOREIGN KEY (album_edition_id)
        REFERENCES ${DatabaseTables.albumEditions}(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

      FOREIGN KEY (artwork_id)
        REFERENCES ${DatabaseTables.artworkAssets}(id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
    )
  ''');
  }

  static Future<void> createAlbumEditionTracks(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.albumEditionTracks} (
        album_edition_id TEXT NOT NULL,
        song_id TEXT NOT NULL,
        disc_number INTEGER NOT NULL DEFAULT 1
          CHECK (disc_number >= 0),
        track_number INTEGER NOT NULL DEFAULT 0
          CHECK (track_number >= 0),
        sort_position INTEGER NOT NULL
          CHECK (sort_position >= 0),
        numbering_authority TEXT NOT NULL DEFAULT 'inferred'
          CHECK (numbering_authority IN ('inferred', 'manual')),
        ordering_authority TEXT NOT NULL DEFAULT 'inferred'
          CHECK (ordering_authority IN ('inferred', 'manual')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        PRIMARY KEY (album_edition_id, song_id),

        FOREIGN KEY (album_edition_id)
          REFERENCES ${DatabaseTables.albumEditions}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,

        FOREIGN KEY (song_id)
          REFERENCES ${DatabaseTables.songs}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_album_edition_tracks_edition_order
      ON ${DatabaseTables.albumEditionTracks}(
        album_edition_id,
        sort_position,
        disc_number,
        track_number
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_album_edition_tracks_song_id
      ON ${DatabaseTables.albumEditionTracks}(song_id)
    ''');
  }

  static Future<void> createSongArtistCredits(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.songArtistCredits} (
        id TEXT PRIMARY KEY NOT NULL,
        song_id TEXT NOT NULL,
        artist_id TEXT,
        credited_name TEXT NOT NULL
          CHECK (length(trim(credited_name)) > 0),
        canonical_credited_name TEXT NOT NULL
          CHECK (length(trim(canonical_credited_name)) > 0),
        role TEXT NOT NULL
          CHECK (role IN ('primary', 'coPrimary', 'featured', 'guest')),
        position INTEGER NOT NULL
          CHECK (position >= 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (song_id)
          REFERENCES ${DatabaseTables.songs}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,

        FOREIGN KEY (artist_id)
          REFERENCES ${DatabaseTables.artists}(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL,

        UNIQUE(song_id, position)
      )
    ''');

    await createSongArtistCreditIndexes(db);
  }

  static Future<void> createSongArtistCreditIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX idx_song_artist_credits_song_position
      ON ${DatabaseTables.songArtistCredits}(song_id, position)
    ''');

    await db.execute('''
      CREATE INDEX idx_song_artist_credits_artist_id
      ON ${DatabaseTables.songArtistCredits}(artist_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_song_artist_credits_canonical_name
      ON ${DatabaseTables.songArtistCredits}(canonical_credited_name)
    ''');
  }

  static Future<void> _createMediaFileBindings(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.mediaFileBindings} (
        id TEXT PRIMARY KEY NOT NULL,
        song_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        normalized_path TEXT NOT NULL,
        source_id TEXT,
        is_available INTEGER NOT NULL DEFAULT 1
          CHECK (is_available IN (0, 1)),
        last_seen_at TEXT,
        file_size_bytes INTEGER
          CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
        modified_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        UNIQUE(normalized_path),

        FOREIGN KEY (source_id)
          REFERENCES ${DatabaseTables.importSources}(id)
          ON UPDATE CASCADE
          ON DELETE SET NULL,

        FOREIGN KEY (song_id)
          REFERENCES ${DatabaseTables.songs}(id)
          ON UPDATE CASCADE
          ON DELETE RESTRICT
      )
    ''');
  }

  static Future<void> createArtworkAssets(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE ${DatabaseTables.artworkAssets} (
      id TEXT PRIMARY KEY NOT NULL,
      file_path TEXT NOT NULL,
      normalized_path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,

      UNIQUE(normalized_path)
    )
  ''');
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX idx_artists_canonical_name
      ON ${DatabaseTables.artists}(canonical_name)
    ''');

    await db.execute('''
      CREATE INDEX idx_albums_artist_id
      ON ${DatabaseTables.albums}(artist_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_albums_artist_canonical_title
      ON ${DatabaseTables.albums}(artist_id, canonical_title)
    ''');

    await db.execute('''
      CREATE INDEX idx_albums_canonical_title
      ON ${DatabaseTables.albums}(canonical_title)
    ''');

    await db.execute('''
      CREATE INDEX idx_album_editions_album_id
      ON ${DatabaseTables.albumEditions}(album_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_songs_artist_id
      ON ${DatabaseTables.songs}(artist_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_songs_album_id
      ON ${DatabaseTables.songs}(album_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_songs_album_edition_id
      ON ${DatabaseTables.songs}(album_edition_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_songs_canonical_title
      ON ${DatabaseTables.songs}(canonical_title)
    ''');

    await db.execute('''
      CREATE INDEX idx_media_file_bindings_song_id
      ON ${DatabaseTables.mediaFileBindings}(song_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_media_file_bindings_available
      ON ${DatabaseTables.mediaFileBindings}(is_available)
    ''');

    await db.execute('''
      CREATE INDEX idx_media_file_bindings_source_id
      ON ${DatabaseTables.mediaFileBindings}(source_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_artists_header_artwork_id
      ON ${DatabaseTables.artists}(header_artwork_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_artists_top_artists_artwork_id
      ON ${DatabaseTables.artists}(top_artists_artwork_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_album_editions_artwork_id
      ON ${DatabaseTables.albumEditions}(artwork_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_songs_artwork_id
      ON ${DatabaseTables.songs}(artwork_id)
    ''');
  }
}
