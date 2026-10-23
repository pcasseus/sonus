import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_backup_exporter.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteBackupExporter exporter;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    exporter = SqliteBackupExporter(
      appDatabase: appDatabase,
      generateId: () => 'backup-test',
      now: () => DateTime.utc(2026, 10, 21),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('exports all 17 portable tables from an empty database', () async {
    final result = await exporter.export();

    expect(result.payload.tables.length, 17);
    expect(result.payload.totalRows, 0);
    expect(result.manifest.totalRows, 0);
    expect(result.manifest.backupId, 'backup-test');
    expect(result.manifest.createdAtUtc.isUtc, isTrue);

    result.payload.validateAgainst(result.manifest);
  });

  test('preserves library identities and parent relationships', () async {
    final db = await appDatabase.database;
    const timestamp = '2026-10-21T00:00:00.000Z';

    await db.insert(DatabaseTables.artists, {
      'id': 'artist-original',
      'name': 'Original Artist',
      'canonical_name': 'original artist',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album-original',
      'artist_id': 'artist-original',
      'title': 'Original Album',
      'canonical_title': 'original album',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final result = await exporter.export();

    final artist = result.payload.tables[DatabaseTables.artists]!.single;
    final album = result.payload.tables[DatabaseTables.albums]!.single;

    expect(artist['id'], 'artist-original');
    expect(album['id'], 'album-original');
    expect(album['artist_id'], 'artist-original');

    expect(result.manifest.rowCounts[DatabaseTables.artists], 1);
    expect(result.manifest.rowCounts[DatabaseTables.albums], 1);
    expect(result.payload.totalRows, 2);

    result.payload.validateAgainst(result.manifest);
  });

  test('does not include device-local or sync tables', () async {
    final result = await exporter.export();

    expect(
      result.payload.tables.containsKey(DatabaseTables.mediaFileBindings),
      isFalse,
    );

    expect(
      result.payload.tables.containsKey(DatabaseTables.syncOutbox),
      isFalse,
    );

    expect(
      result.payload.tables.containsKey(DatabaseTables.localAccountBinding),
      isFalse,
    );
  });

  test('exports artwork playlists and historical charts', () async {
    final db = await appDatabase.database;
    const timestamp = '2026-10-21T00:00:00.000Z';

    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork-original',
      'file_path': '/old-device/artwork/cover.jpg',
      'normalized_path': '/old-device/artwork/cover.jpg',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.playlists, {
      'id': 'playlist-original',
      'name': 'My Favorites',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.insert(DatabaseTables.chartSnapshots, {
      'id': 'chart-original',
      'chart_type': 'songs',
      'week_start_utc': '2026-10-12T00:00:00.000Z',
      'week_end_utc': '2026-10-19T00:00:00.000Z',
      'finalized_at': timestamp,
      'revision': 1,
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    final result = await exporter.export();

    final artwork = result.payload.tables[DatabaseTables.artworkAssets]!.single;
    final playlist = result.payload.tables[DatabaseTables.playlists]!.single;
    final snapshot =
        result.payload.tables[DatabaseTables.chartSnapshots]!.single;

    expect(artwork['id'], 'artwork-original');
    expect(artwork['file_path'], '/old-device/artwork/cover.jpg');

    expect(playlist['id'], 'playlist-original');
    expect(playlist['name'], 'My Favorites');

    expect(snapshot['id'], 'chart-original');
    expect(snapshot['chart_type'], 'songs');
    expect(snapshot['revision'], 1);
    expect(snapshot['week_start_utc'], '2026-10-12T00:00:00.000Z');

    expect(result.manifest.rowCounts[DatabaseTables.artworkAssets], 1);
    expect(result.manifest.rowCounts[DatabaseTables.playlists], 1);
    expect(result.manifest.rowCounts[DatabaseTables.chartSnapshots], 1);
    expect(result.payload.totalRows, 3);

    result.payload.validateAgainst(result.manifest);
  });
  test('preserves connected music history and chart data', () async {
    final db = await appDatabase.database;
    const time = '2026-10-21T00:00:00.000Z';
    const weekStart = '2026-10-12T00:00:00.000Z';
    const weekEnd = '2026-10-19T00:00:00.000Z';

    await db.insert(DatabaseTables.artists, {
      'id': 'artist-1',
      'name': 'Original Artist',
      'canonical_name': 'original artist',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album-1',
      'artist_id': 'artist-1',
      'title': 'Original Album',
      'canonical_title': 'original album',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition-1',
      'album_id': 'album-1',
      'title': 'Standard Edition',
      'type': 'standard',
      'is_primary': 1,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.songs, {
      'id': 'song-1',
      'artist_id': 'artist-1',
      'album_id': 'album-1',
      'album_edition_id': 'edition-1',
      'title': 'Original Song',
      'canonical_title': 'original song',
      'track_number': 1,
      'duration_seconds': 210,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.albumEditionTracks, {
      'album_edition_id': 'edition-1',
      'song_id': 'song-1',
      'disc_number': 1,
      'track_number': 1,
      'sort_position': 0,
      'numbering_authority': 'manual',
      'ordering_authority': 'manual',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.songArtistCredits, {
      'id': 'credit-1',
      'song_id': 'song-1',
      'artist_id': 'artist-1',
      'credited_name': 'Original Artist',
      'canonical_credited_name': 'original artist',
      'role': 'primary',
      'position': 0,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.playlists, {
      'id': 'playlist-1',
      'name': 'My Favorites',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.playlistItems, {
      'id': 'item-1',
      'playlist_id': 'playlist-1',
      'song_id': 'song-1',
      'position': 0,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.trackLyrics, {
      'song_id': 'song-1',
      'plain_text': 'Original lyrics',
      'synced_text': '[00:01.00]Original lyrics',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'session-1',
      'user_id': 'historical-user',
      'song_id': 'song-1',
      'artist_id': 'artist-1',
      'album_id': 'album-1',
      'album_edition_id': 'edition-1',
      'song_title': 'Original Song',
      'artist_name': 'Original Artist',
      'album_title': 'Original Album',
      'album_edition_title': 'Standard Edition',
      'started_at': time,
      'ended_at': '2026-10-21T00:03:30.000Z',
      'listened_duration_ms': 210000,
      'track_duration_ms': 210000,
      'final_position_ms': 210000,
      'end_reason': 'completed',
      'source_context': 'playlist',
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.playbackListeningSegments, {
      'id': 'segment-1',
      'playback_session_id': 'session-1',
      'started_at': time,
      'ended_at': '2026-10-21T00:03:30.000Z',
      'listened_duration_ms': 210000,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': 'qualified-1',
      'playback_session_id': 'session-1',
      'user_id': 'historical-user',
      'song_id': 'song-1',
      'artist_id': 'artist-1',
      'album_id': 'album-1',
      'album_edition_id': 'edition-1',
      'qualified_at': time,
      'listened_duration_ms': 210000,
      'track_duration_ms': 210000,
      'created_at': time,
    });

    await db.insert(DatabaseTables.chartSnapshots, {
      'id': 'snapshot-1',
      'chart_type': 'songs',
      'week_start_utc': weekStart,
      'week_end_utc': weekEnd,
      'finalized_at': time,
      'revision': 1,
      'created_at': time,
      'updated_at': time,
    });

    await db.insert(DatabaseTables.chartEntries, {
      'id': 'chart-entry-1',
      'chart_snapshot_id': 'snapshot-1',
      'entity_id': 'song-1',
      'title': 'Original Song',
      'artist_id': 'artist-1',
      'artist_name': 'Original Artist',
      'album_title': 'Original Album',
      'rank': 3,
      'qualified_stream_count': 125,
      'previous_final_rank': 7,
      'peak_rank': 2,
      'peak_achieved_at': weekStart,
      'weeks_on_chart': 5,
      'movement': 'up',
      'last_qualified_at': time,
      'created_at': time,
      'updated_at': time,
    });

    final result = await exporter.export();

    final connectedTables = [
      DatabaseTables.artists,
      DatabaseTables.albums,
      DatabaseTables.albumEditions,
      DatabaseTables.songs,
      DatabaseTables.albumEditionTracks,
      DatabaseTables.songArtistCredits,
      DatabaseTables.playlists,
      DatabaseTables.playlistItems,
      DatabaseTables.trackLyrics,
      DatabaseTables.playbackSessions,
      DatabaseTables.playbackListeningSegments,
      DatabaseTables.qualifiedPlays,
      DatabaseTables.chartSnapshots,
      DatabaseTables.chartEntries,
    ];

    expect(result.payload.totalRows, connectedTables.length);

    for (final table in connectedTables) {
      final originalRows = await db.query(table);
      final exportedRows = result.payload.tables[table]!;

      expect(originalRows, hasLength(1), reason: table);
      expect(exportedRows, originalRows, reason: table);
      expect(result.manifest.rowCounts[table], 1);
    }

    final qualifiedPlay =
        result.payload.tables[DatabaseTables.qualifiedPlays]!.single;

    expect(qualifiedPlay['playback_session_id'], 'session-1');
    expect(qualifiedPlay['listened_duration_ms'], 210000);
    expect(qualifiedPlay['user_id'], 'historical-user');

    final chartEntry =
        result.payload.tables[DatabaseTables.chartEntries]!.single;

    expect(chartEntry['rank'], 3);
    expect(chartEntry['previous_final_rank'], 7);
    expect(chartEntry['qualified_stream_count'], 125);
    expect(chartEntry['movement'], 'up');

    final lyrics = result.payload.tables[DatabaseTables.trackLyrics]!.single;

    expect(lyrics['plain_text'], 'Original lyrics');
    expect(lyrics['synced_text'], '[00:01.00]Original lyrics');

    result.payload.validateAgainst(result.manifest);
  });
  test('records the actual matching source database version', () async {
    final db = await appDatabase.database;
    final versionRows = await db.rawQuery('PRAGMA user_version');

    expect(versionRows.single['user_version'], AppDatabase.databaseVersion);

    final result = await exporter.export();

    expect(result.manifest.databaseVersion, versionRows.single['user_version']);
  });

  test('rejects mismatched source database versions', () async {
    final db = await appDatabase.database;

    for (final version in [
      AppDatabase.databaseVersion - 1,
      AppDatabase.databaseVersion + 1,
    ]) {
      await db.execute('PRAGMA user_version = $version');

      await expectLater(
        exporter.export(),
        throwsFormatException,
        reason: 'Unexpectedly accepted schema version $version',
      );
    }
  });
  test('queues a library write until export completes', () async {
    final db = await appDatabase.database;
    final firstTableRead = Completer<void>();
    final continueExport = Completer<void>();

    final pausedExporter = SqliteBackupExporter(
      appDatabase: appDatabase,
      generateId: () => 'concurrent-backup',
      now: () => DateTime.utc(2026, 10, 21),
      afterTableRead: (table) async {
        if (table == DatabaseTables.artists) {
          firstTableRead.complete();
          await continueExport.future;
        }
      },
    );

    final exportFuture = pausedExporter.export();

    await firstTableRead.future;

    final writeFuture = db.insert(DatabaseTables.artists, {
      'id': 'artist-after-snapshot',
      'name': 'Later Artist',
      'canonical_name': 'later artist',
      'created_at': '2026-10-21T00:00:00.000Z',
      'updated_at': '2026-10-21T00:00:00.000Z',
    });

    continueExport.complete();

    final exportResult = await exportFuture;
    await writeFuture;

    expect(exportResult.payload.tables[DatabaseTables.artists], isEmpty);

    expect(exportResult.manifest.rowCounts[DatabaseTables.artists], 0);

    final laterRows = await db.query(DatabaseTables.artists);

    expect(laterRows, hasLength(1));
    expect(laterRows.single['id'], 'artist-after-snapshot');

    final subsequentExport = await exporter.export();

    expect(subsequentExport.manifest.rowCounts[DatabaseTables.artists], 1);
  });
  test('exporting does not modify the local library', () async {
    final db = await appDatabase.database;

    final before = await db.query(DatabaseTables.artists);

    await exporter.export();

    final after = await db.query(DatabaseTables.artists);

    expect(after, before);
  });
}
