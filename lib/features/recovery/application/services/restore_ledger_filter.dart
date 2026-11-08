import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../../library/data/repositories/merge_history_remap.dart';

/// App Update 1.2: a restore never brings back what this device deleted
/// or merged on purpose (the deletion ledger and journal stay on the device
/// through a restore).
///
/// Applied to the backup's rows before they are written:
/// - records the user permanently deleted are dropped, with their listening
///   history, chart weeks from the earliest recalculated week on (rebuilt
///   from the remaining plays afterwards), Moments, playlist entries and
///   other dependants;
/// - records merged into another are dropped, and history that belonged to
///   them follows the record that stayed.
///
/// Merges are followed along their whole chain (A merged into B, later B
/// into C, resolves A to C), and a record counts as deleted when any record
/// on its chain was deleted by the user: history of a duplicate merged into
/// a song that was deleted later stays deleted. A chain that loops cannot
/// be resolved: [MergeChainException] is thrown and the restore, which runs
/// in one transaction, changes nothing.
class RestoreLedgerFilter {
  RestoreLedgerFilter._(this._ledger, this._chains, this._chartsFrom);

  /// entity type → ids, for every ledger row.
  final Map<String, Set<String>> _ledger;

  /// Every merge this device knows.
  final MergeChains _chains;

  /// The earliest chart week a deletion or merge recalculated, if any.
  final String? _chartsFrom;

  static Future<RestoreLedgerFilter> load(DatabaseExecutor db) async {
    final ledger = <String, Set<String>>{};
    final userDeleted = <String, Set<String>>{};
    for (final row in await db.query(DatabaseTables.libraryDeletionLedger)) {
      final type = row['entity_type']! as String;
      final id = row['entity_id']! as String;
      (ledger[type] ??= {}).add(id);
      if (row['reason'] == 'userDeletion') (userDeleted[type] ??= {}).add(id);
    }
    String? chartsFrom;
    for (final row in await db.query(DatabaseTables.libraryDeletionJournal)) {
      // Deletions and merges from another device that met stored charts
      // both list the weeks they recalculated.
      for (final week
          in (jsonDecode(row['rebuilt_weeks']! as String) as List)
              .cast<String>()) {
        final start = week.contains(':')
            ? week.substring(week.indexOf(':') + 1)
            : week;
        if (chartsFrom == null || start.compareTo(chartsFrom) < 0) {
          chartsFrom = start;
        }
      }
    }
    final merges = await MergeHistoryRemap.load(db);
    final filter = RestoreLedgerFilter._(ledger, merges.chains, chartsFrom);
    filter._userDeleted.addAll(userDeleted);
    return filter;
  }

  final Map<String, Set<String>> _userDeleted = {};

  bool get isEmpty => _ledger.isEmpty && _chains.isEmpty;

  bool _in(String type, Object? id) =>
      id is String && _ledger[type]?.contains(id) == true;

  /// Ledger entity type → merge chain kind.
  static const _chainKinds = {
    'song': 'songs',
    'album': 'albums',
    'albumEdition': 'editions',
  };

  /// Whether [id], or a record it was merged into, was deleted by the user.
  bool _deletedByUser(String type, Object? id) {
    final deleted = _userDeleted[type];
    if (id is! String || deleted == null) return false;
    final kind = _chainKinds[type];
    return kind == null
        ? deleted.contains(id)
        : _chains.chainHitsAny(kind, id, deleted);
  }

  String? _follow(String key, Object? id) => _chains.resolveValue(key, id);

  /// The filtered tables, and how many rows each lost (for the restore's
  /// row-count verification).
  ({Map<String, List<Map<String, Object?>>> tables, Map<String, int> removed})
  apply(Map<String, List<Map<String, Object?>>> tables) {
    if (isEmpty) return (tables: tables, removed: const {});

    final out = <String, List<Map<String, Object?>>>{...tables};
    final removed = <String, int>{};

    void keep(
      String table,
      Map<String, Object?>? Function(Map<String, Object?> row) transform,
    ) {
      final rows = tables[table];
      if (rows == null) return;
      final kept = <Map<String, Object?>>[];
      for (final row in rows) {
        final next = transform(row);
        if (next != null) kept.add(next);
      }
      if (kept.length != rows.length) {
        removed[table] = rows.length - kept.length;
      }
      out[table] = kept;
    }

    final droppedAlbums = <String>{};
    final droppedEditions = <String>{};
    final droppedSongs = <String>{};
    final droppedArtists = <String>{};

    keep(DatabaseTables.artists, (row) {
      if (!_in('artist', row['id'])) return row;
      droppedArtists.add(row['id']! as String);
      return null;
    });
    keep(DatabaseTables.albums, (row) {
      if (!_in('album', row['id']) &&
          !droppedArtists.contains(row['artist_id'])) {
        return row;
      }
      droppedAlbums.add(row['id']! as String);
      return null;
    });
    keep(DatabaseTables.albumEditions, (row) {
      if (!_in('albumEdition', row['id']) &&
          !droppedAlbums.contains(row['album_id'])) {
        return row;
      }
      droppedEditions.add(row['id']! as String);
      return null;
    });
    keep(DatabaseTables.songs, (row) {
      if (!_in('song', row['id']) &&
          !droppedAlbums.contains(row['album_id']) &&
          !droppedEditions.contains(row['album_edition_id']) &&
          !droppedArtists.contains(row['artist_id'])) {
        return row;
      }
      droppedSongs.add(row['id']! as String);
      return null;
    });

    keep(
      DatabaseTables.albumEditionTracks,
      (row) =>
          droppedSongs.contains(row['song_id']) ||
              droppedEditions.contains(row['album_edition_id'])
          ? null
          : row,
    );
    keep(DatabaseTables.songArtistCredits, (row) {
      if (droppedSongs.contains(row['song_id'])) return null;
      return droppedArtists.contains(row['artist_id'])
          ? {...row, 'artist_id': null}
          : row;
    });
    keep(
      DatabaseTables.trackLyrics,
      (row) => droppedSongs.contains(row['song_id']) ? null : row,
    );
    keep(DatabaseTables.metadataFieldStates, (row) {
      final id = row['entity_id'];
      final dropped = switch (row['entity_type']) {
        'song' => droppedSongs.contains(id),
        'album' => droppedAlbums.contains(id),
        'albumEdition' => droppedEditions.contains(id),
        'artist' => droppedArtists.contains(id),
        _ => false,
      };
      return dropped ? null : row;
    });

    // Listening history: wiped with what the user deleted; otherwise it
    // follows a merged record to the one that stayed.
    final droppedSessions = <String>{};
    Map<String, Object?>? history(Map<String, Object?> row, String idType) {
      if (_in(idType, row['id']) || _deletedByUser('song', row['song_id'])) {
        return null;
      }
      return {
        ...row,
        'song_id': _follow('songs', row['song_id']),
        'album_id': _follow('albums', row['album_id']),
        'album_edition_id': _follow('editions', row['album_edition_id']),
      };
    }

    keep(DatabaseTables.playbackSessions, (row) {
      final next = history(row, 'playbackSession');
      if (next == null) droppedSessions.add(row['id']! as String);
      return next;
    });
    keep(
      DatabaseTables.playbackListeningSegments,
      (row) =>
          droppedSessions.contains(row['playback_session_id']) ? null : row,
    );
    keep(DatabaseTables.qualifiedPlays, (row) {
      if (droppedSessions.contains(row['playback_session_id'])) return null;
      return history(row, 'qualifiedPlay');
    });

    // Charts from the first recalculated week on are rebuilt from the
    // remaining plays after the restore, never restored with ghosts. A
    // backup week that still ranks a merged duplicate is rebuilt too (D3),
    // so no chart row points at a record that no longer exists (BUG-00B).
    var from = _chartsFrom;
    if (!_chains.isEmpty) {
      final weekOf = {
        for (final row in tables[DatabaseTables.chartSnapshots] ?? const [])
          row['id']: row['week_start_utc']! as String,
      };
      for (final row in tables[DatabaseTables.chartEntries] ?? const []) {
        final id = row['entity_id'];
        if (id is! String ||
            !(_chains.isMerged('songs', id) ||
                _chains.isMerged('albums', id))) {
          continue;
        }
        final week = weekOf[row['chart_snapshot_id']];
        if (week != null && (from == null || week.compareTo(from) < 0)) {
          from = week;
        }
      }
    }
    final chartsFrom = from;
    final droppedSnapshots = <String>{};
    keep(DatabaseTables.chartSnapshots, (row) {
      if (chartsFrom == null ||
          (row['week_start_utc']! as String).compareTo(chartsFrom) < 0) {
        return row;
      }
      droppedSnapshots.add(row['id']! as String);
      return null;
    });
    keep(DatabaseTables.chartEntries, (row) {
      if (droppedSnapshots.contains(row['chart_snapshot_id'])) return null;
      return _deletedByUser('song', row['entity_id']) ||
              _deletedByUser('album', row['entity_id'])
          ? null
          : row;
    });
    keep(DatabaseTables.chartMomentEvents, (row) {
      if (_in('moment', row['deduplication_key'])) return null;
      for (final column in ['entity_id', 'related_entity_id']) {
        for (final type in ['song', 'album', 'artist']) {
          if (_deletedByUser(type, row[column])) return null;
        }
      }
      for (final column in ['entity_artist_id', 'related_entity_artist_id']) {
        if (_deletedByUser('artist', row[column])) return null;
      }
      // A story about a merged duplicate is about the record that stayed.
      if (_chains.isEmpty) return row;
      final kind = row['chart_type'] == 'albums' ? 'albums' : 'songs';
      return {
        ...row,
        'entity_id': _follow(kind, row['entity_id']),
        if (row['related_entity_id'] != null)
          'related_entity_id': _follow(kind, row['related_entity_id']),
      };
    });

    // Playlists keep their place; deleted songs leave, merged ones follow.
    final seen = <(Object?, Object?)>{};
    final touched = <Object?>{};
    keep(DatabaseTables.playlistItems, (row) {
      if (_deletedByUser('song', row['song_id'])) {
        touched.add(row['playlist_id']);
        return null;
      }
      final song = _follow('songs', row['song_id']);
      if (!seen.add((row['playlist_id'], song))) {
        touched.add(row['playlist_id']);
        return null;
      }
      return {...row, 'song_id': song};
    });
    if (touched.isNotEmpty) {
      final items = out[DatabaseTables.playlistItems]!;
      for (final playlistId in touched) {
        final inPlaylist =
            items.where((i) => i['playlist_id'] == playlistId).toList()..sort(
              (a, b) =>
                  (a['position']! as int).compareTo(b['position']! as int),
            );
        for (final (index, item) in inPlaylist.indexed) {
          item['position'] = index;
        }
      }
    }

    final classified = <Object?>{};
    keep(DatabaseTables.albumReleaseClassifications, (row) {
      final album = _follow('albums', row['album_id']);
      if (droppedAlbums.contains(album) || !classified.add(album)) return null;
      return {...row, 'album_id': album};
    });
    keep(DatabaseTables.artistProjectAssignments, (row) {
      if (droppedArtists.contains(row['artist_id'])) return null;
      final album = row['album_id'] == null
          ? null
          : _follow('albums', row['album_id']);
      if (album != null && droppedAlbums.contains(album)) return null;
      return {...row, 'album_id': album};
    });
    keep(DatabaseTables.artworkCrops, (row) {
      final target = row['target_id'];
      return switch (row['target_type']) {
        'albumEdition' => droppedEditions.contains(target) ? null : row,
        'artistBanner' ||
        'artistPortrait' => droppedArtists.contains(target) ? null : row,
        _ => row,
      };
    });

    return (tables: out, removed: removed);
  }
}
