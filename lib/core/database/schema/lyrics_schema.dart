import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class LyricsSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.trackLyrics} (
        song_id TEXT PRIMARY KEY NOT NULL,
        plain_text TEXT,
        synced_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (song_id)
          REFERENCES ${DatabaseTables.songs}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
  }
}
