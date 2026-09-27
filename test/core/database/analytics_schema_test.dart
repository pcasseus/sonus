import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  const artistId = 'artist_analytics';
  const albumId = 'album_analytics';
  const editionId = 'edition_analytics';
  const songId = 'song_analytics';

  const now = '2026-09-25T12:00:00.000Z';

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await LibrarySchema.create(db);
          await AnalyticsSchema.create(db);
        },
      ),
    );

    await database.insert(DatabaseTables.artists, {
      'id': artistId,
      'name': 'Analytics Artist',
      'canonical_name': 'analytics artist',
      'is_blacklisted': 0,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albums, {
      'id': albumId,
      'artist_id': artistId,
      'title': 'Analytics Album',
      'canonical_title': 'analytics album',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albumEditions, {
      'id': editionId,
      'album_id': albumId,
      'title': 'Analytics Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'title': 'Analytics Song',
      'canonical_title': 'analytics song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 240,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await database.close();
  });

  test('creates playback session and qualified play tables', () async {
    final rows = await database.rawQuery(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (?, ?)
        ORDER BY name
      ''',
      [DatabaseTables.playbackSessions, DatabaseTables.qualifiedPlays],
    );

    expect(rows.map((row) => row['name']), [
      DatabaseTables.playbackSessions,
      DatabaseTables.qualifiedPlays,
    ]);
  });

  test('playback session stores detailed listening history', () async {
    await database.insert(DatabaseTables.playbackSessions, {
      'id': 'session_1',
      'user_id': null,
      'song_id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'song_title': 'Historical Song',
      'artist_name': 'Historical Artist',
      'album_title': 'Historical Album',
      'album_edition_title': 'Historical Edition',
      'started_at': now,
      'ended_at': '2026-09-25T12:00:45.000Z',
      'listened_duration_ms': 45000,
      'track_duration_ms': 240000,
      'final_position_ms': 45000,
      'end_reason': 'skipped',
      'source_context': 'library',
      'created_at': now,
      'updated_at': '2026-09-25T12:00:45.000Z',
    });

    final rows = await database.query(DatabaseTables.playbackSessions);

    expect(rows, hasLength(1));
    expect(rows.single['song_id'], songId);
    expect(rows.single['album_edition_id'], editionId);
    expect(rows.single['song_title'], 'Historical Song');
    expect(rows.single['artist_name'], 'Historical Artist');
    expect(rows.single['album_title'], 'Historical Album');
    expect(rows.single['album_edition_title'], 'Historical Edition');
    expect(rows.single['listened_duration_ms'], 45000);
    expect(rows.single['end_reason'], 'skipped');
  });

  test('qualified play allows only one play per playback session', () async {
    await database.insert(DatabaseTables.playbackSessions, {
      'id': 'session_qualified',
      'user_id': null,
      'song_id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'song_title': 'Historical Song',
      'artist_name': 'Historical Artist',
      'album_title': 'Historical Album',
      'album_edition_title': 'Historical Edition',
      'started_at': now,
      'ended_at': null,
      'listened_duration_ms': 30000,
      'track_duration_ms': 240000,
      'final_position_ms': 30000,
      'end_reason': null,
      'source_context': 'library',
      'created_at': now,
      'updated_at': now,
    });

    final qualifiedPlay = <String, Object?>{
      'id': 'play_1',
      'playback_session_id': 'session_qualified',
      'user_id': null,
      'song_id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'qualified_at': '2026-09-25T12:00:30.000Z',
      'listened_duration_ms': 30000,
      'track_duration_ms': 240000,
      'created_at': '2026-09-25T12:00:30.000Z',
    };

    await database.insert(DatabaseTables.qualifiedPlays, qualifiedPlay);

    await expectLater(
      database.insert(DatabaseTables.qualifiedPlays, {
        ...qualifiedPlay,
        'id': 'play_2',
      }),
      throwsA(anything),
    );
  });

  test('rejects invalid playback session end reasons', () async {
    await expectLater(
      database.insert(DatabaseTables.playbackSessions, {
        'id': 'session_invalid_end',
        'user_id': null,
        'song_id': songId,
        'artist_id': artistId,
        'album_id': albumId,
        'album_edition_id': editionId,
        'song_title': 'Historical Song',
        'artist_name': 'Historical Artist',
        'album_title': 'Historical Album',
        'album_edition_title': 'Historical Edition',
        'started_at': now,
        'ended_at': now,
        'listened_duration_ms': 1000,
        'track_duration_ms': 240000,
        'final_position_ms': 1000,
        'end_reason': 'made_up_reason',
        'source_context': 'library',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('rejects negative listened duration', () async {
    await expectLater(
      database.insert(DatabaseTables.playbackSessions, {
        'id': 'session_negative_duration',
        'user_id': null,
        'song_id': songId,
        'artist_id': artistId,
        'album_id': albumId,
        'album_edition_id': editionId,
        'song_title': 'Historical Song',
        'artist_name': 'Historical Artist',
        'album_title': 'Historical Album',
        'album_edition_title': 'Historical Edition',
        'started_at': now,
        'ended_at': now,
        'listened_duration_ms': -1,
        'track_duration_ms': 240000,
        'final_position_ms': 0,
        'end_reason': 'failed',
        'source_context': 'library',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('creates analytics query indexes', () async {
    final rows = await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND (
            tbl_name = '${DatabaseTables.playbackSessions}'
            OR tbl_name = '${DatabaseTables.qualifiedPlays}'
          )
      ''');

    final names = rows.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'idx_playback_sessions_started_at',
        'idx_playback_sessions_song_started',
        'idx_playback_sessions_artist_started',
        'idx_playback_sessions_album_started',
        'idx_playback_sessions_edition_started',
        'idx_qualified_plays_qualified_at',
        'idx_qualified_plays_song_qualified',
        'idx_qualified_plays_artist_qualified',
        'idx_qualified_plays_album_qualified',
        'idx_qualified_plays_edition_qualified',
      }),
    );
  });

  test('library deletion does not remove or block analytics history', () async {
    final now = DateTime.utc(2026, 9, 25, 12).toIso8601String();

    await database.insert(DatabaseTables.artists, {
      'id': 'artist_history',
      'name': 'History Artist',
      'canonical_name': 'history artist',
      'is_blacklisted': 0,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albums, {
      'id': 'album_history',
      'artist_id': 'artist_history',
      'title': 'History Album',
      'canonical_title': 'history album',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albumEditions, {
      'id': 'edition_history',
      'album_id': 'album_history',
      'title': 'History Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.songs, {
      'id': 'song_history',
      'artist_id': 'artist_history',
      'album_id': 'album_history',
      'album_edition_id': 'edition_history',
      'title': 'History Song',
      'canonical_title': 'history song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.playbackSessions, {
      'id': 'session_history',
      'song_id': 'song_history',
      'artist_id': 'artist_history',
      'album_id': 'album_history',
      'album_edition_id': 'edition_history',
      'song_title': 'Historical Song',
      'artist_name': 'Historical Artist',
      'album_title': 'Historical Album',
      'album_edition_title': 'Historical Edition',
      'started_at': now,
      'ended_at': now,
      'listened_duration_ms': 30000,
      'track_duration_ms': 180000,
      'final_position_ms': 30000,
      'end_reason': 'stopped',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.qualifiedPlays, {
      'id': 'play_history',
      'playback_session_id': 'session_history',
      'song_id': 'song_history',
      'artist_id': 'artist_history',
      'album_id': 'album_history',
      'album_edition_id': 'edition_history',
      'qualified_at': now,
      'listened_duration_ms': 30000,
      'track_duration_ms': 180000,
      'created_at': now,
    });

    await database.delete(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_history'],
    );

    await database.delete(
      DatabaseTables.albumEditions,
      where: 'id = ?',
      whereArgs: ['edition_history'],
    );

    await database.delete(
      DatabaseTables.albums,
      where: 'id = ?',
      whereArgs: ['album_history'],
    );

    await database.delete(
      DatabaseTables.artists,
      where: 'id = ?',
      whereArgs: ['artist_history'],
    );

    final sessions = await database.query(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['session_history'],
    );

    final plays = await database.query(
      DatabaseTables.qualifiedPlays,
      where: 'id = ?',
      whereArgs: ['play_history'],
    );

    expect(sessions, hasLength(1));
    expect(plays, hasLength(1));

    expect(sessions.single['song_id'], 'song_history');
    expect(sessions.single['artist_id'], 'artist_history');
    expect(sessions.single['album_id'], 'album_history');
    expect(sessions.single['album_edition_id'], 'edition_history');

    expect(sessions.single['song_title'], 'Historical Song');
    expect(sessions.single['artist_name'], 'Historical Artist');
    expect(sessions.single['album_title'], 'Historical Album');
    expect(sessions.single['album_edition_title'], 'Historical Edition');

    expect(plays.single['song_id'], 'song_history');
    expect(plays.single['artist_id'], 'artist_history');
    expect(plays.single['album_id'], 'album_history');
    expect(plays.single['album_edition_id'], 'edition_history');
  });

  test('creates playback listening segment table and indexes', () async {
    final tables = await database.rawQuery(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = ?
      ''',
      [DatabaseTables.playbackListeningSegments],
    );

    expect(tables, hasLength(1));

    final indexes = await database.rawQuery(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND tbl_name = ?
      ''',
      [DatabaseTables.playbackListeningSegments],
    );

    final names = indexes.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      containsAll({
        'idx_playback_listening_segments_session',
        'idx_playback_listening_segments_started_at',
        'idx_playback_listening_segments_ended_at',
        'idx_playback_listening_segments_one_open_per_session',
      }),
    );
  });

  test(
    'allows at most one open listening segment per playback session',
    () async {
      await database.insert(DatabaseTables.playbackSessions, {
        'id': 'session_one_open_segment',
        'song_id': songId,
        'artist_id': artistId,
        'album_id': albumId,
        'album_edition_id': editionId,
        'song_title': 'Open Segment Song',
        'artist_name': 'Open Segment Artist',
        'album_title': 'Open Segment Album',
        'album_edition_title': 'Open Segment Edition',
        'started_at': now,
        'ended_at': null,
        'listened_duration_ms': 0,
        'track_duration_ms': 240000,
        'final_position_ms': 0,
        'end_reason': null,
        'created_at': now,
        'updated_at': now,
      });

      await database.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'segment_open_1',
        'playback_session_id': 'session_one_open_segment',
        'started_at': now,
        'ended_at': null,
        'listened_duration_ms': 0,
        'created_at': now,
        'updated_at': now,
      });

      await expectLater(
        database.insert(DatabaseTables.playbackListeningSegments, {
          'id': 'segment_open_2',
          'playback_session_id': 'session_one_open_segment',
          'started_at': '2026-09-25T12:00:05.000Z',
          'ended_at': null,
          'listened_duration_ms': 0,
          'created_at': '2026-09-25T12:00:05.000Z',
          'updated_at': '2026-09-25T12:00:05.000Z',
        }),
        throwsA(anything),
      );

      await database.update(
        DatabaseTables.playbackListeningSegments,
        {
          'ended_at': '2026-09-25T12:00:10.000Z',
          'updated_at': '2026-09-25T12:00:10.000Z',
        },
        where: 'id = ?',
        whereArgs: ['segment_open_1'],
      );

      await database.insert(DatabaseTables.playbackListeningSegments, {
        'id': 'segment_open_2',
        'playback_session_id': 'session_one_open_segment',
        'started_at': '2026-09-25T12:00:15.000Z',
        'ended_at': null,
        'listened_duration_ms': 0,
        'created_at': '2026-09-25T12:00:15.000Z',
        'updated_at': '2026-09-25T12:00:15.000Z',
      });

      final openRows = await database.query(
        DatabaseTables.playbackListeningSegments,
        where: 'playback_session_id = ? AND ended_at IS NULL',
        whereArgs: ['session_one_open_segment'],
      );

      expect(openRows, hasLength(1));
      expect(openRows.single['id'], 'segment_open_2');
    },
  );
  test('playback session deletion cascades listening segments', () async {
    await database.insert(DatabaseTables.playbackSessions, {
      'id': 'session_segment_cascade',
      'song_id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'song_title': 'Historical Song',
      'artist_name': 'Historical Artist',
      'album_title': 'Historical Album',
      'album_edition_title': 'Historical Edition',
      'started_at': now,
      'ended_at': null,
      'listened_duration_ms': 10000,
      'track_duration_ms': 240000,
      'final_position_ms': 10000,
      'end_reason': null,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'segment_cascade',
      'playback_session_id': 'session_segment_cascade',
      'started_at': now,
      'ended_at': null,
      'listened_duration_ms': 10000,
      'created_at': now,
      'updated_at': now,
    });

    await database.delete(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['session_segment_cascade'],
    );

    final segments = await database.query(
      DatabaseTables.playbackListeningSegments,
      where: 'id = ?',
      whereArgs: ['segment_cascade'],
    );

    expect(segments, isEmpty);
  });
}
