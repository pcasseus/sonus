import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sonus_next/core/database/database_tables.dart';

// Library seeding and snapshot helpers with no FFI dependency, so they
// run both in host tests and in on-device integration tests.

const fixtureTimestamp = '2026-10-21T00:00:00.000Z';

/// Inserts one connected library graph touching every portable table.
///
/// [key] namespaces identities; [week] keeps chart weeks unique when
/// several graphs share a database.
Future<void> seedConnectedLibrary(
  DatabaseExecutor db, {
  required String key,
  int week = 0,
  String? userId,
  String? artworkPath,
  String songTitle = 'Song',
}) async {
  final weekStart = DateTime.utc(2026, 1, 5).add(Duration(days: 7 * week));
  final weekEnd = weekStart.add(const Duration(days: 7));
  final artworkId = artworkPath == null ? null : 'artwork-$key';

  if (artworkPath != null) {
    await db.insert(DatabaseTables.artworkAssets, {
      'id': artworkId,
      'file_path': artworkPath,
      'normalized_path': artworkPath.replaceAll('\\', '/').toLowerCase(),
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });
  }

  await db.insert(DatabaseTables.artists, {
    'id': 'artist-$key',
    'name': 'Artist $key',
    'canonical_name': 'artist $key',
    'header_artwork_id': artworkId,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.albums, {
    'id': 'album-$key',
    'artist_id': 'artist-$key',
    'title': 'Album $key',
    'canonical_title': 'album $key',
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition-$key',
    'album_id': 'album-$key',
    'title': 'Standard',
    'type': 'standard',
    'is_primary': 1,
    'artwork_id': artworkId,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.songs, {
    'id': 'song-$key',
    'artist_id': 'artist-$key',
    'album_id': 'album-$key',
    'album_edition_id': 'edition-$key',
    'title': songTitle,
    'canonical_title': songTitle.toLowerCase(),
    'track_number': 1,
    'duration_seconds': 200,
    'artwork_id': artworkId,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.albumEditionTracks, {
    'album_edition_id': 'edition-$key',
    'song_id': 'song-$key',
    'sort_position': 0,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.songArtistCredits, {
    'id': 'credit-$key',
    'song_id': 'song-$key',
    'artist_id': 'artist-$key',
    'credited_name': 'Artist $key',
    'canonical_credited_name': 'artist $key',
    'role': 'primary',
    'position': 0,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.metadataFieldStates, {
    'entity_type': 'song',
    'entity_id': 'song-$key',
    'field_name': 'title',
    'authority': 'manual',
    'source': 'user',
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.trackLyrics, {
    'song_id': 'song-$key',
    'plain_text': 'Lyrics $key',
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.playbackSessions, {
    'id': 'session-$key',
    'user_id': userId,
    'song_id': 'song-$key',
    'artist_id': 'artist-$key',
    'album_id': 'album-$key',
    'album_edition_id': 'edition-$key',
    'song_title': songTitle,
    'artist_name': 'Artist $key',
    'album_title': 'Album $key',
    'album_edition_title': 'Standard',
    'started_at': fixtureTimestamp,
    'ended_at': fixtureTimestamp,
    'listened_duration_ms': 200000,
    'track_duration_ms': 200000,
    'final_position_ms': 200000,
    'end_reason': 'completed',
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.playbackListeningSegments, {
    'id': 'segment-$key',
    'playback_session_id': 'session-$key',
    'started_at': fixtureTimestamp,
    'ended_at': fixtureTimestamp,
    'listened_duration_ms': 200000,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.qualifiedPlays, {
    'id': 'play-$key',
    'playback_session_id': 'session-$key',
    'user_id': userId,
    'song_id': 'song-$key',
    'artist_id': 'artist-$key',
    'album_id': 'album-$key',
    'album_edition_id': 'edition-$key',
    'qualified_at': fixtureTimestamp,
    'listened_duration_ms': 200000,
    'track_duration_ms': 200000,
    'created_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.chartSnapshots, {
    'id': 'snapshot-$key',
    'chart_type': 'songs',
    'week_start_utc': weekStart.toIso8601String(),
    'week_end_utc': weekEnd.toIso8601String(),
    'finalized_at': fixtureTimestamp,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.chartEntries, {
    'id': 'entry-$key',
    'chart_snapshot_id': 'snapshot-$key',
    'entity_id': 'song-$key',
    'title': songTitle,
    'artist_id': 'artist-$key',
    'artist_name': 'Artist $key',
    'rank': 1,
    'qualified_stream_count': 3,
    'peak_rank': 1,
    'peak_achieved_at': weekStart.toIso8601String(),
    'weeks_on_chart': 1,
    'movement': 'newEntry',
    'last_qualified_at': fixtureTimestamp,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.chartMomentEvents, {
    'id': 'moment-$key',
    'deduplication_key': 'moment-$key',
    'user_id': userId,
    'chart_type': 'songs',
    'scope': 'finalized',
    'event_type': 'debut',
    'entity_id': 'song-$key',
    'entity_title': songTitle,
    'entity_artist_name': 'Artist $key',
    'week_start_utc': weekStart.toIso8601String(),
    'week_end_utc': weekEnd.toIso8601String(),
    'occurred_at': fixtureTimestamp,
    'created_at': fixtureTimestamp,
    'current_rank': 1,
  });

  await db.insert(DatabaseTables.playlists, {
    'id': 'playlist-$key',
    'name': 'Playlist $key',
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });

  await db.insert(DatabaseTables.playlistItems, {
    'id': 'item-$key',
    'playlist_id': 'playlist-$key',
    'song_id': 'song-$key',
    'position': 0,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });
}

/// Device-local audio link for a seeded song.
Future<void> seedMediaBinding(
  DatabaseExecutor db, {
  required String key,
  bool available = true,
}) async {
  final filePath = '/device/music/$key.mp3';

  await db.insert(DatabaseTables.mediaFileBindings, {
    'id': 'binding-$key',
    'song_id': 'song-$key',
    'file_path': filePath,
    'normalized_path': filePath,
    'is_available': available ? 1 : 0,
    'created_at': fixtureTimestamp,
    'updated_at': fixtureTimestamp,
  });
}

Future<void> seedImportReview(DatabaseExecutor db, {required String key}) =>
    db.insert(DatabaseTables.songImportReviews, {
      'song_id': 'song-$key',
      'metadata_source': 'embedded',
      'created_at': fixtureTimestamp,
      'updated_at': fixtureTimestamp,
    });

/// Every row of every table, for exact before/after comparisons.
Future<Map<String, List<Map<String, Object?>>>> snapshotDatabase(
  DatabaseExecutor db,
) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );

  return {
    for (final row in tables)
      row['name'] as String: await db.rawQuery(
        'SELECT * FROM "${row['name']}" ORDER BY rowid',
      ),
  };
}

/// Paths and bytes of every file below [directory].
Future<Map<String, List<int>>> snapshotFiles(Directory directory) async {
  final files = <String, List<int>>{};
  if (!await directory.exists()) return files;

  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) files[entity.path] = await entity.readAsBytes();
  }

  return files;
}
