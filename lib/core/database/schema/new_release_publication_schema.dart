import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

/// Published new-release debut stories (App Update 1.3, database version
/// 48, user decision 2026-11-16): one row per song, written once when the
/// story is first shown, so later library edits never rewrite it.
///
/// Keyed by the existing Song ID, with no foreign key to songs or to the
/// chart Moment it tells, like chart_moment_events: removing a song row
/// never deletes published history. Permanent deletion removes it with the
/// song's Moments; a duplicate merge moves it to the song that stays
/// unless that song has its own. Kept in local backups; not synced.
///
/// A correction process is not built. It would update a row in place,
/// raise `revision` and set `corrected_at` (both or neither).
abstract final class NewReleasePublicationSchema {
  static const String table = DatabaseTables.newReleaseDebutPublications;

  static Future<void> create(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS $table (
      song_id TEXT PRIMARY KEY NOT NULL,
      story_id TEXT NOT NULL,
      event_id TEXT NOT NULL,
      event_deduplication_key TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('single', 'albumTrack')),
      chart_scope TEXT NOT NULL CHECK (chart_scope IN ('finalized', 'allTime')),
      chart_rank INTEGER NOT NULL CHECK (chart_rank BETWEEN 1 AND 200),
      chart_name TEXT NOT NULL,
      week_start_utc TEXT NOT NULL,
      debuted_at_utc TEXT NOT NULL,
      song_title TEXT NOT NULL,
      artist_name TEXT NOT NULL,
      featured_artists TEXT NOT NULL DEFAULT '[]',
      album_id TEXT,
      album_title TEXT,
      album_format TEXT CHECK (album_format IS NULL
                               OR album_format IN ('album', 'ep')),
      release_date TEXT NOT NULL,
      release_date_precision TEXT NOT NULL
        CHECK (release_date_precision IN ('year', 'month', 'day')),
      headline TEXT NOT NULL,
      published_at TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
      corrected_at TEXT,
      CHECK ((revision = 1) = (corrected_at IS NULL)),
      CHECK ((kind = 'albumTrack') = (album_title IS NOT NULL)),
      CHECK ((kind = 'albumTrack') = (album_format IS NOT NULL)),
      CHECK ((release_date_precision = 'year'
              AND release_date GLOB '[0-9][0-9][0-9][0-9]')
        OR (release_date_precision = 'month'
            AND release_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]')
        OR (release_date_precision = 'day'
            AND release_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'))
    )
  ''');
}
