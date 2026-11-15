import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// A song's own presentation as a Single (App Update 1.3, REF-1.3-04,
/// database version 47): its single release date and dedicated cover.
///
/// One row per Song ID, never a new song: plays, charts, Moments,
/// playlists, file bindings and album placements stay on the song. The
/// row is kept when the song stops being a Single (`songs.is_single`), so
/// switching it back restores the presentation. It goes with the song when
/// the song is permanently deleted. Album artwork and edition dates are
/// never touched. Kept in local backups; not synced to the cloud.
///
/// The release date is stored as text in the shape its precision allows:
/// 'YYYY' (year), 'YYYY-MM' (month) or 'YYYY-MM-DD' (day); both are set or
/// both are null. Impossible dates (2026-02-30) are refused in Dart.
abstract final class SongSinglePresentationSchema {
  static Future<void> create(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.songSinglePresentations} (
      song_id TEXT PRIMARY KEY NOT NULL,
      release_date TEXT,
      release_date_precision TEXT
        CHECK (release_date_precision IS NULL
               OR release_date_precision IN ('year', 'month', 'day')),
      artwork_id TEXT,
      use_artwork_in_charts INTEGER NOT NULL DEFAULT 0
        CHECK (use_artwork_in_charts IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((release_date IS NULL) = (release_date_precision IS NULL)),
      CHECK (release_date IS NULL
        OR (release_date_precision = 'year'
            AND release_date GLOB '[0-9][0-9][0-9][0-9]')
        OR (release_date_precision = 'month'
            AND release_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]')
        OR (release_date_precision = 'day'
            AND release_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]')),
      FOREIGN KEY (song_id)
        REFERENCES ${DatabaseTables.songs}(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
      FOREIGN KEY (artwork_id)
        REFERENCES ${DatabaseTables.artworkAssets}(id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
    )
  ''');
}
