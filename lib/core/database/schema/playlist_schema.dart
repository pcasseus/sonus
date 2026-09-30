import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class PlaylistSchema {
  static Future<void> create(Database db) async {
    await createPlaylists(db);
    await createPlaylistItems(db);
    await createIndexes(db);
  }

  static Future<void> createPlaylists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.playlists} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> createPlaylistItems(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.playlistItems} (
        id TEXT PRIMARY KEY,
        playlist_id TEXT NOT NULL
          REFERENCES ${DatabaseTables.playlists}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        song_id TEXT NOT NULL
          REFERENCES ${DatabaseTables.songs}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK (position >= 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (playlist_id, song_id)
      )
    ''');
  }

  static Future<void> createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_playlist_items_playlist_position
      ON ${DatabaseTables.playlistItems}(playlist_id, position)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_playlist_items_song_id
      ON ${DatabaseTables.playlistItems}(song_id)
    ''');
  }
}
