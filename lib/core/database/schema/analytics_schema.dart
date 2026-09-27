import 'package:sqflite/sqflite.dart';

import '../database_tables.dart';

abstract final class AnalyticsSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await createPlaybackSessions(db);
    await createPlaybackListeningSegments(db);
    await createQualifiedPlays(db);
    await createIndexes(db);
  }

  static Future<void> createPlaybackSessions(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.playbackSessions} (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT,
        song_id TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        album_id TEXT NOT NULL,
        album_edition_id TEXT NOT NULL,

        song_title TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_title TEXT NOT NULL,
        album_edition_title TEXT NOT NULL,

        started_at TEXT NOT NULL,
        ended_at TEXT,

        listened_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (listened_duration_ms >= 0),
        track_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (track_duration_ms >= 0),

        final_position_ms INTEGER NOT NULL DEFAULT 0
          CHECK (final_position_ms >= 0),

        end_reason TEXT
          CHECK (
            end_reason IS NULL OR
            end_reason IN (
              'completed',
              'skipped',
              'stopped',
              'replaced',
              'interrupted',
              'failed'
            )
          ),

        source_context TEXT,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> createPlaybackListeningSegments(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.playbackListeningSegments} (
        id TEXT PRIMARY KEY NOT NULL,
        playback_session_id TEXT NOT NULL,

        started_at TEXT NOT NULL,
        ended_at TEXT,

        listened_duration_ms INTEGER NOT NULL DEFAULT 0
          CHECK (listened_duration_ms >= 0),

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,

        FOREIGN KEY (playback_session_id)
          REFERENCES ${DatabaseTables.playbackSessions}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> createQualifiedPlays(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.qualifiedPlays} (
        id TEXT PRIMARY KEY NOT NULL,
        playback_session_id TEXT NOT NULL UNIQUE,
        user_id TEXT,
        song_id TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        album_id TEXT NOT NULL,
        album_edition_id TEXT NOT NULL,

        qualified_at TEXT NOT NULL,

        listened_duration_ms INTEGER NOT NULL
          CHECK (listened_duration_ms >= 0),
        track_duration_ms INTEGER NOT NULL
          CHECK (track_duration_ms >= 0),

        created_at TEXT NOT NULL,

        FOREIGN KEY (playback_session_id)
          REFERENCES ${DatabaseTables.playbackSessions}(id)
          ON UPDATE CASCADE
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> createIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX idx_playback_sessions_started_at
      ON ${DatabaseTables.playbackSessions}(started_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_sessions_song_started
      ON ${DatabaseTables.playbackSessions}(song_id, started_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_sessions_artist_started
      ON ${DatabaseTables.playbackSessions}(artist_id, started_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_sessions_album_started
      ON ${DatabaseTables.playbackSessions}(album_id, started_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_sessions_edition_started
      ON ${DatabaseTables.playbackSessions}(album_edition_id, started_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_listening_segments_session
      ON ${DatabaseTables.playbackListeningSegments}(playback_session_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_listening_segments_started_at
      ON ${DatabaseTables.playbackListeningSegments}(started_at)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_playback_listening_segments_one_open_per_session
      ON ${DatabaseTables.playbackListeningSegments}(playback_session_id)
      WHERE ended_at IS NULL
    ''');

    await db.execute('''
      CREATE INDEX idx_playback_listening_segments_ended_at
      ON ${DatabaseTables.playbackListeningSegments}(ended_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_qualified_plays_qualified_at
      ON ${DatabaseTables.qualifiedPlays}(qualified_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_qualified_plays_song_qualified
      ON ${DatabaseTables.qualifiedPlays}(song_id, qualified_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_qualified_plays_artist_qualified
      ON ${DatabaseTables.qualifiedPlays}(artist_id, qualified_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_qualified_plays_album_qualified
      ON ${DatabaseTables.qualifiedPlays}(album_id, qualified_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_qualified_plays_edition_qualified
      ON ${DatabaseTables.qualifiedPlays}(album_edition_id, qualified_at)
    ''');
  }
}
