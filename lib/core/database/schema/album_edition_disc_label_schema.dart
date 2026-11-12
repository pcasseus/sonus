import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// Optional names for an edition's discs ("Bonus Tracks", "Live
/// Performances"), one per edition and disc number (App Update 1.2,
/// REF-13c, database version 45).
///
/// A label belongs to its disc number, never to the songs on it: moving
/// songs between discs or reordering them leaves it where it is. It goes
/// with its edition when the edition is deleted. Kept in local backups;
/// not synced to the cloud yet.
abstract final class AlbumEditionDiscLabelSchema {
  static Future<void> create(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.albumEditionDiscLabels} (
      album_edition_id TEXT NOT NULL,
      disc_number INTEGER NOT NULL CHECK (disc_number >= 1),
      label TEXT NOT NULL CHECK (length(trim(label)) > 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (album_edition_id, disc_number),
      FOREIGN KEY (album_edition_id)
        REFERENCES ${DatabaseTables.albumEditions}(id)
        ON DELETE CASCADE
    )
  ''');
}
