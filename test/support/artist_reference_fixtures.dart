// Rows that refer to an artist, for artist retirement tests (A1, A2).
// Inserted straight into a real SQLite library.
import 'package:sqflite/sqflite.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/sync_schema.dart';

const _time = '2026-10-27T12:00:00.000Z';

class ArtistReferenceFixtures {
  ArtistReferenceFixtures(this.db);

  final DatabaseExecutor db;
  var _next = 0;

  String _id(String prefix) => '$prefix-${++_next}';

  Future<void> artist(String id, [String? name]) {
    final artistName = name ?? 'Artist $id';
    return db.insert(DatabaseTables.artists, {
      'id': id,
      'name': artistName,
      'canonical_name': artistName.toLowerCase(),
      'is_blacklisted': 0,
      'created_at': _time,
      'updated_at': _time,
    });
  }

  /// An album with one primary edition; returns the album id.
  Future<String> album(String artistId) async {
    final albumId = _id('album');
    await db.insert(DatabaseTables.albums, {
      'id': albumId,
      'artist_id': artistId,
      'title': '$albumId title',
      'canonical_title': '$albumId title',
      'created_at': _time,
      'updated_at': _time,
    });
    await db.insert(DatabaseTables.albumEditions, {
      'id': '$albumId-edition',
      'album_id': albumId,
      'title': '$albumId title',
      'type': 'standard',
      'is_primary': 1,
      'created_at': _time,
      'updated_at': _time,
    });
    return albumId;
  }

  /// A song by [artistId] on [albumId] (a new album of the same artist
  /// when omitted); returns the song id.
  Future<String> song(String artistId, {String? albumId}) async {
    final owner = albumId ?? await album(artistId);
    final songId = _id('song');
    await db.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': artistId,
      'album_id': owner,
      'album_edition_id': '$owner-edition',
      'title': '$songId title',
      'canonical_title': '$songId title',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 180,
      'is_single': 0,
      'is_blocked': 0,
      'featured_artists': '[]',
      'created_at': _time,
      'updated_at': _time,
    });
    return songId;
  }

  Future<void> credit(
    String songId,
    String artistId, {
    String role = 'featured',
  }) {
    return db.insert(DatabaseTables.songArtistCredits, {
      'id': _id('credit'),
      'song_id': songId,
      'artist_id': artistId,
      'credited_name': 'Artist $artistId',
      'canonical_credited_name': 'artist $artistId',
      'role': role,
      'position': 1,
      'created_at': _time,
      'updated_at': _time,
    });
  }

  Future<void> assignment(String artistId) {
    return db.insert(DatabaseTables.artistProjectAssignments, {
      'artist_id': artistId,
      'mode': 'standalone',
      'created_at': _time,
      'updated_at': _time,
    });
  }

  /// A playback session; returns its id.
  Future<String> session(String artistId) async {
    final id = _id('session');
    await db.insert(DatabaseTables.playbackSessions, {
      'id': id,
      'song_id': 'song-gone',
      'artist_id': artistId,
      'album_id': 'album-gone',
      'album_edition_id': 'edition-gone',
      'song_title': 'Song',
      'artist_name': 'Kept Artist',
      'album_title': 'Album',
      'album_edition_title': 'Standard',
      'started_at': _time,
      'created_at': _time,
      'updated_at': _time,
    });
    return id;
  }

  /// A qualified play, with its own session by the same artist.
  Future<void> play(String artistId) async {
    final sessionId = await session(artistId);
    await db.insert(DatabaseTables.qualifiedPlays, {
      'id': _id('play'),
      'playback_session_id': sessionId,
      'song_id': 'song-gone',
      'artist_id': artistId,
      'album_id': 'album-gone',
      'album_edition_id': 'edition-gone',
      'qualified_at': _time,
      'listened_duration_ms': 60000,
      'track_duration_ms': 180000,
      'created_at': _time,
    });
  }

  /// A chart entry in the week starting [week] (a snapshot per call).
  Future<void> chartEntry(
    String artistId, {
    String week = '2026-10-24T00:00:00.000Z',
    String chartType = 'songs',
  }) async {
    final snapshotId = _id('snapshot');
    await db.insert(DatabaseTables.chartSnapshots, {
      'id': snapshotId,
      'chart_type': chartType,
      'week_start_utc': week,
      'week_end_utc': DateTime.parse(
        week,
      ).add(const Duration(days: 7)).toIso8601String(),
      'finalized_at': _time,
      'created_at': _time,
      'updated_at': _time,
    });
    await db.insert(DatabaseTables.chartEntries, {
      'id': _id('entry'),
      'chart_snapshot_id': snapshotId,
      'entity_id': 'song-gone',
      'title': 'Song',
      'artist_id': artistId,
      'artist_name': 'Kept Artist',
      'rank': 1,
      'qualified_stream_count': 4,
      'peak_rank': 1,
      'peak_achieved_at': _time,
      'movement': 'newEntry',
      'last_qualified_at': _time,
      'created_at': _time,
      'updated_at': _time,
    });
  }

  Future<void> moment({String? entityArtistId, String? relatedArtistId}) {
    final id = _id('moment');
    return db.insert(DatabaseTables.chartMomentEvents, {
      'id': id,
      'deduplication_key': 'key-$id',
      'chart_type': 'songs',
      'scope': 'finalized',
      'event_type': 'debut',
      'entity_id': 'song-gone',
      'entity_title': 'Song',
      'entity_artist_id': entityArtistId,
      'entity_artist_name': 'Someone',
      if (relatedArtistId != null) ...{
        'related_entity_id': 'song-other',
        'related_entity_title': 'Other Song',
        'related_entity_artist_id': relatedArtistId,
        'related_entity_artist_name': 'Kept Artist',
      },
      'week_start_utc': '2026-10-24T00:00:00.000Z',
      'week_end_utc': '2026-10-31T00:00:00.000Z',
      'occurred_at': _time,
      'created_at': _time,
    });
  }

  /// An artist write not yet confirmed with the cloud.
  Future<void> pendingWrite(String artistId) {
    return db.insert(SyncSchema.artistWriteJournalTable, {
      'user_id': 'user_1',
      'artist_id': artistId,
      'outbox_id': _id('outbox'),
      'mutation_revision': 1,
      'operation': 'create',
      'request_json': '{}',
      'created_at': _time,
    });
  }

  /// Row counts of every table that refers to artists, to prove a read
  /// changed nothing.
  Future<Map<String, int>> referenceRowCounts() async {
    final counts = <String, int>{};
    for (final table in [
      DatabaseTables.artists,
      DatabaseTables.albums,
      DatabaseTables.songs,
      DatabaseTables.songArtistCredits,
      DatabaseTables.artistProjectAssignments,
      DatabaseTables.playbackSessions,
      DatabaseTables.qualifiedPlays,
      DatabaseTables.chartSnapshots,
      DatabaseTables.chartEntries,
      DatabaseTables.chartMomentEvents,
      SyncSchema.artistWriteJournalTable,
      SyncSchema.artistDependencyJournalTable,
    ]) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
      counts[table] = rows.single['n']! as int;
    }
    return counts;
  }
}
