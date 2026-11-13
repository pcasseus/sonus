import 'dart:convert';

import '../../../library/data/repositories/merge_history_remap.dart';
import '../../../library/application/services/remote_library_deletion_applier.dart';
import '../../../library/data/repositories/sqlite_library_deletion_ledger.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/database/schema/sync_schema.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../application/services/cloud_archive_sync_service.dart';
import '../../domain/models/cloud_archive_record.dart';

/// Reads archive records from, and applies them to, the local database.
class SqliteCloudArchiveStore implements CloudArchiveLocalStore {
  SqliteCloudArchiveStore({
    required this.appDatabase,
    LibraryChangeSignal? changes,
    DateTime Function()? now,
  }) : _changes = changes ?? LibraryChangeSignal.shared,
       _now = now ?? DateTime.now;

  final AppDatabase appDatabase;
  final LibraryChangeSignal _changes;
  final DateTime Function() _now;

  static const _cursorEntity = 'archive';

  /// The table each kind's main row lives in.
  static const _tables = {
    CloudArchiveKind.lyrics: DatabaseTables.trackLyrics,
    CloudArchiveKind.artworkCrop: DatabaseTables.artworkCrops,
    CloudArchiveKind.releaseClassification:
        DatabaseTables.albumReleaseClassifications,
    CloudArchiveKind.projectAssignment: DatabaseTables.artistProjectAssignments,
    CloudArchiveKind.allTimeMoment: DatabaseTables.chartMomentEvents,
  };

  @override
  Future<List<CloudArchiveRecord>> collect() async {
    final db = await appDatabase.database;
    return [
      ...await _playlists(db),
      ...await _sessions(db),
      ...await _deletions(db),
      for (final row in await db.query(DatabaseTables.trackLyrics))
        _record(CloudArchiveKind.lyrics, row['song_id']! as String, row),
      for (final row in await db.query(DatabaseTables.artworkCrops))
        _record(
          CloudArchiveKind.artworkCrop,
          '${row['target_type']}:${row['target_id']}',
          row,
        ),
      for (final row in await db.query(
        DatabaseTables.albumReleaseClassifications,
      ))
        _record(
          CloudArchiveKind.releaseClassification,
          row['album_id']! as String,
          row,
        ),
      for (final row in await db.query(DatabaseTables.artistProjectAssignments))
        _record(
          CloudArchiveKind.projectAssignment,
          row['artist_id']! as String,
          row,
        ),
      for (final row in await db.query(
        DatabaseTables.chartMomentEvents,
        where: 'scope = ?',
        whereArgs: ['allTime'],
      ))
        _record(
          CloudArchiveKind.allTimeMoment,
          row['deduplication_key']! as String,
          row,
          updatedColumn: 'created_at',
        ),
    ];
  }

  Future<List<CloudArchiveRecord>> _playlists(Database db) async {
    final items = <String, List<Map<String, Object?>>>{};
    for (final row in await db.query(
      DatabaseTables.playlistItems,
      orderBy: 'playlist_id, position, id',
    )) {
      items.putIfAbsent(row['playlist_id']! as String, () => []).add({...row});
    }
    return [
      for (final row in await db.query(DatabaseTables.playlists))
        CloudArchiveRecord(
          kind: CloudArchiveKind.playlist,
          key: row['id']! as String,
          payload: {
            ...row,
            'items': [
              for (final item in items[row['id']] ?? const [])
                {
                  for (final e in item.entries)
                    if (e.key != 'playlist_id') e.key: e.value,
                },
            ],
          },
          clientUpdatedAt: _latest([
            row['updated_at'],
            for (final item in items[row['id']] ?? const []) item['updated_at'],
          ]),
        ),
    ];
  }

  /// Finished sessions only: one still in progress keeps changing.
  Future<List<CloudArchiveRecord>> _sessions(Database db) async {
    final segments = <String, List<Map<String, Object?>>>{};
    for (final row in await db.query(
      DatabaseTables.playbackListeningSegments,
      orderBy: 'playback_session_id, started_at, id',
    )) {
      segments.putIfAbsent(row['playback_session_id']! as String, () => []).add(
        {...row},
      );
    }
    final plays = {
      for (final row in await db.query(DatabaseTables.qualifiedPlays))
        row['playback_session_id']! as String: row,
    };
    return [
      for (final row in await db.query(
        DatabaseTables.playbackSessions,
        where: 'ended_at IS NOT NULL',
      ))
        CloudArchiveRecord(
          kind: CloudArchiveKind.listeningSession,
          key: row['id']! as String,
          payload: {
            'session': {...row},
            'segments': segments[row['id']] ?? const [],
            'qualified_play': plays[row['id']],
          },
          clientUpdatedAt: _latest([row['updated_at']]),
        ),
    ];
  }

  CloudArchiveRecord _record(
    CloudArchiveKind kind,
    String key,
    Map<String, Object?> row, {
    String updatedColumn = 'updated_at',
  }) => CloudArchiveRecord(
    kind: kind,
    key: key,
    payload: {...row},
    clientUpdatedAt: _latest([row[updatedColumn]]),
  );

  static DateTime _latest(List<Object?> stamps) {
    var latest = DateTime.utc(1970);
    for (final stamp in stamps) {
      final parsed = stamp is String ? DateTime.tryParse(stamp) : null;
      if (parsed != null && parsed.isAfter(latest)) latest = parsed.toUtc();
    }
    return latest;
  }

  @override
  Future<CloudArchiveApplyOutcome> apply(CloudArchiveRecord record) async {
    final outcome = await appDatabase.transaction(
      (txn) => _applyIn(txn, record),
    );
    if (outcome == CloudArchiveApplyOutcome.applied) {
      _changes.notify(
        record.kind == CloudArchiveKind.listeningSession
            ? LibraryChangeKind.listeningRecorded
            : LibraryChangeKind.libraryEdited,
      );
    }
    return outcome;
  }

  Future<CloudArchiveApplyOutcome> _applyIn(
    Transaction txn,
    CloudArchiveRecord record,
  ) async {
    final payload = record.payload;
    switch (record.kind) {
      case CloudArchiveKind.playlist:
        // Entries for songs the user permanently deleted here are dropped
        // instead of holding the whole playlist back (App Update 1.2).
        // A merged duplicate's entry follows its whole merge chain to the
        // song that stayed, once per playlist, and is dropped when that
        // song was deleted later (BUG-00A, BUG-00C).
        final playlistLedger = SqliteLibraryDeletionLedger(txn);
        final playlistMerges = (await MergeHistoryRemap.load(txn)).chains;
        final items = <Map<String, Object?>>[];
        final placed = <String>{};
        var dropped = false;
        for (final raw in (payload['items'] as List? ?? const [])) {
          final item = Map<String, Object?>.from(raw as Map);
          final song = item['song_id'];
          final List<String> chain;
          try {
            chain = song is String
                ? playlistMerges.path('songs', song)
                : const [];
          } on MergeChainException {
            return CloudArchiveApplyOutcome.missingDependencies;
          }
          if (await playlistLedger.anyDeletedByUser(
            DeletionLedgerEntity.song,
            chain,
          )) {
            dropped = true;
            continue;
          }
          if (chain.isNotEmpty) {
            if (!placed.add(chain.last)) {
              dropped = true;
              continue;
            }
            item['song_id'] = chain.last;
          }
          items.add(item);
        }
        if (dropped) {
          items.sort(
            (a, b) => ((a['position'] as int?) ?? 0).compareTo(
              (b['position'] as int?) ?? 0,
            ),
          );
          for (final (index, item) in items.indexed) {
            item['position'] = index;
          }
        }
        for (final item in items) {
          if (!await _exists(
            txn,
            DatabaseTables.songs,
            'id',
            item['song_id'],
          )) {
            return CloudArchiveApplyOutcome.missingDependencies;
          }
        }
        final playlist = {
          for (final e in payload.entries)
            if (e.key != 'items') e.key: e.value,
        };
        await _upsert(txn, DatabaseTables.playlists, playlist, ['id']);
        await txn.delete(
          DatabaseTables.playlistItems,
          where: 'playlist_id = ?',
          whereArgs: [record.key],
        );
        for (final item in items) {
          await _insert(txn, DatabaseTables.playlistItems, {
            ...item,
            'playlist_id': record.key,
          }, ConflictAlgorithm.abort);
        }

      case CloudArchiveKind.listeningSession:
        final session = Map<String, Object?>.from(payload['session'] as Map);
        final play = payload['qualified_play'];
        // App Update 1.2: listening the user permanently deleted here, or
        // of a song they deleted, never comes back from the archive. The
        // song is checked along its whole merge chain (BUG-00A): a play of
        // a duplicate merged into a song that was deleted later is deleted
        // listening too.
        final ledger = SqliteLibraryDeletionLedger(txn);
        final merges = await MergeHistoryRemap.load(txn);
        final List<String> songChain;
        try {
          songChain = [
            for (final id in {
              session['song_id'],
              if (play is Map) play['song_id'],
            })
              if (id is String) ...merges.chains.path('songs', id),
          ];
        } on MergeChainException {
          // A merge chain that loops cannot be placed safely: nothing is
          // written, and the record is offered again on a later sync.
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        if (await ledger.contains(
              DeletionLedgerEntity.playbackSession,
              session['id'] as String?,
            ) ||
            await ledger.anyDeletedByUser(
              DeletionLedgerEntity.song,
              songChain,
            )) {
          return CloudArchiveApplyOutcome.deletedHere;
        }
        // Listening of a release merged here follows the one that stayed,
        // through every merge after it.
        final Map<String, Object?> followedSession;
        final Map<String, Object?>? followedPlay;
        try {
          followedSession = merges.follow(session);
          followedPlay = play is Map
              ? merges.follow(Map<String, Object?>.from(play))
              : null;
        } on MergeChainException {
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        await _insert(
          txn,
          DatabaseTables.playbackSessions,
          followedSession,
          ConflictAlgorithm.ignore,
        );
        for (final segment in (payload['segments'] as List? ?? const [])) {
          await _insert(
            txn,
            DatabaseTables.playbackListeningSegments,
            Map<String, Object?>.from(segment as Map),
            ConflictAlgorithm.ignore,
          );
        }
        if (followedPlay != null) {
          await _insert(
            txn,
            DatabaseTables.qualifiedPlays,
            followedPlay,
            ConflictAlgorithm.ignore,
          );
        }

      case CloudArchiveKind.lyrics:
        if (!await _exists(
          txn,
          DatabaseTables.songs,
          'id',
          payload['song_id'],
        )) {
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        await _upsert(txn, _tables[record.kind]!, payload, ['song_id']);

      case CloudArchiveKind.artworkCrop:
        for (final column in ['source_artwork_id', 'output_artwork_id']) {
          if (!await _exists(
            txn,
            DatabaseTables.artworkAssets,
            'id',
            payload[column],
          )) {
            return CloudArchiveApplyOutcome.missingDependencies;
          }
        }
        await _upsert(txn, _tables[record.kind]!, payload, [
          'target_type',
          'target_id',
        ]);

      case CloudArchiveKind.releaseClassification:
        if (!await _exists(
          txn,
          DatabaseTables.albums,
          'id',
          payload['album_id'],
        )) {
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        await _upsert(txn, _tables[record.kind]!, payload, ['album_id']);

      case CloudArchiveKind.projectAssignment:
        final album = payload['album_id'];
        if (!await _exists(
              txn,
              DatabaseTables.artists,
              'id',
              payload['artist_id'],
            ) ||
            (album != null &&
                !await _exists(txn, DatabaseTables.albums, 'id', album))) {
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        await _upsert(txn, _tables[record.kind]!, payload, ['artist_id']);

      case CloudArchiveKind.allTimeMoment:
        // Stories deleted with their subject never come back either.
        final ledger = SqliteLibraryDeletionLedger(txn);
        if (await ledger.contains(DeletionLedgerEntity.moment, record.key)) {
          return CloudArchiveApplyOutcome.deletedHere;
        }
        // Songs and releases are checked along their merge chains
        // (BUG-00A), and a story about a merged duplicate is filed under
        // the record that stayed (BUG-00B), as it is when the merge itself
        // arrives.
        final momentMerges = (await MergeHistoryRemap.load(txn)).chains;
        final moment = {...payload};
        try {
          for (final (entity, kind, column) in [
            (DeletionLedgerEntity.song, 'songs', 'entity_id'),
            (DeletionLedgerEntity.album, 'albums', 'entity_id'),
            (DeletionLedgerEntity.artist, null, 'entity_id'),
            (DeletionLedgerEntity.song, 'songs', 'related_entity_id'),
            (DeletionLedgerEntity.album, 'albums', 'related_entity_id'),
            (DeletionLedgerEntity.artist, null, 'entity_artist_id'),
          ]) {
            final id = payload[column];
            if (id is! String) continue;
            final chain = kind == null ? [id] : momentMerges.path(kind, id);
            if (await ledger.anyDeletedByUser(entity, chain)) {
              return CloudArchiveApplyOutcome.deletedHere;
            }
          }
          final kind = payload['chart_type'] == 'albums' ? 'albums' : 'songs';
          for (final column in ['entity_id', 'related_entity_id']) {
            final id = payload[column];
            if (id is String) moment[column] = momentMerges.resolve(kind, id);
          }
        } on MergeChainException {
          return CloudArchiveApplyOutcome.missingDependencies;
        }
        await _insert(
          txn,
          _tables[record.kind]!,
          moment,
          ConflictAlgorithm.ignore,
        );

      case CloudArchiveKind.libraryDeletion:
        // App Update 1.2: a deletion or merge made on another device holds
        // here too. Waits (changing nothing) for what it depends on.
        final applied = await RemoteLibraryDeletionApplier(
          appDatabase: appDatabase,
          now: _now,
        ).apply(txn, record.key, payload);
        if (!applied) return CloudArchiveApplyOutcome.missingDependencies;
    }
    return CloudArchiveApplyOutcome.applied;
  }

  @override
  Future<bool> deletedHere(CloudArchiveKind kind, String key) async {
    final ledger = SqliteLibraryDeletionLedger(await appDatabase.database);
    return switch (kind) {
      CloudArchiveKind.listeningSession => ledger.deletedByUser(
        DeletionLedgerEntity.playbackSession,
        key,
      ),
      CloudArchiveKind.allTimeMoment => ledger.deletedByUser(
        DeletionLedgerEntity.moment,
        key,
      ),
      _ => Future.value(false),
    };
  }

  /// Every deletion and merge this device knows (its own and other
  /// devices'), as library_deletion records.
  Future<List<CloudArchiveRecord>> _deletions(Database db) async {
    final ledger = <String, List<Map<String, Object?>>>{};
    for (final row in await db.query(
      DatabaseTables.libraryDeletionLedger,
      orderBy: 'entity_type, entity_id',
    )) {
      (ledger[row['operation_id']! as String] ??= []).add(row);
    }
    return [
      for (final journal in await db.query(
        DatabaseTables.libraryDeletionJournal,
        orderBy: 'committed_at, id',
      ))
        CloudArchiveRecord(
          kind: CloudArchiveKind.libraryDeletion,
          key: journal['id']! as String,
          payload: LibraryDeletionRecord.payload(
            journal: journal,
            ledger: ledger[journal['id']] ?? const [],
            summary: (jsonDecode(journal['summary']! as String) as Map)
                .cast<String, Object?>(),
          ),
          clientUpdatedAt:
              DateTime.tryParse(journal['committed_at']! as String)?.toUtc() ??
              _now().toUtc(),
        ),
    ];
  }

  static Future<bool> _exists(
    DatabaseExecutor db,
    String table,
    String column,
    Object? value,
  ) async {
    if (value == null) return false;
    final rows = await db.query(
      table,
      columns: [column],
      where: '$column = ?',
      whereArgs: [value],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Only columns this database has are written, so a record from a newer
  /// app version never breaks the insert.
  static Future<Map<String, Object?>> _known(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
  ) async {
    final columns = {
      for (final column in await db.rawQuery('PRAGMA table_info("$table")'))
        column['name']! as String,
    };
    return {
      for (final e in row.entries)
        if (columns.contains(e.key)) e.key: _sqlValue(e.value),
    };
  }

  static Object? _sqlValue(Object? value) => switch (value) {
    final bool flag => flag ? 1 : 0,
    final num number => number,
    final String text => text,
    null => null,
    _ => throw const FormatException('Unsupported archive value.'),
  };

  static Future<void> _insert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
    ConflictAlgorithm onConflict,
  ) async {
    await db.insert(
      table,
      await _known(db, table, row),
      conflictAlgorithm: onConflict,
    );
  }

  static Future<void> _upsert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
    List<String> keyColumns,
  ) async {
    final values = await _known(db, table, row);
    final where = keyColumns.map((c) => '$c = ?').join(' AND ');
    final keys = [for (final c in keyColumns) values[c]];
    final updated = await db.update(
      table,
      values,
      where: where,
      whereArgs: keys,
    );
    if (updated == 0) await db.insert(table, values);
  }

  @override
  Future<void> duplicatePlaylist({
    required Map<String, Object?> payload,
    required String newId,
    required String newName,
  }) async {
    await appDatabase.transaction((txn) async {
      final stamp = _now().toUtc().toIso8601String();
      await _insert(txn, DatabaseTables.playlists, {
        'id': newId,
        'name': newName,
        'created_at': stamp,
        'updated_at': stamp,
      }, ConflictAlgorithm.abort);
      var position = 0;
      for (final item in (payload['items'] as List? ?? const [])) {
        final map = Map<String, Object?>.from(item as Map);
        if (!await _exists(txn, DatabaseTables.songs, 'id', map['song_id'])) {
          continue;
        }
        await _insert(txn, DatabaseTables.playlistItems, {
          'id': '${newId}_$position',
          'playlist_id': newId,
          'song_id': map['song_id'],
          'position': position++,
          'created_at': stamp,
          'updated_at': stamp,
        }, ConflictAlgorithm.ignore);
      }
    });
    _changes.notify(LibraryChangeKind.libraryEdited);
  }

  @override
  Future<bool> artworkInCloud(String userId, String artworkId) async {
    final db = await appDatabase.database;
    final rows = await db.query(
      SyncSchema.cloudRevisionBaselinesTable,
      columns: ['server_revision'],
      where: 'user_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [userId, 'artworkAsset', artworkId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Map<String, CloudArchiveState>> states(String userId) async {
    final db = await appDatabase.database;
    return {
      for (final row in await db.query(
        DatabaseTables.cloudArchiveState,
        where: 'user_id = ?',
        whereArgs: [userId],
      ))
        '${row['kind']}:${row['record_key']}': CloudArchiveState(
          fingerprint: row['fingerprint']! as String,
          serverRevision: row['server_revision']! as int,
          pendingApply: row['pending_apply'] == 1,
          cloudDeleted: row['cloud_deleted'] == 1,
        ),
    };
  }

  @override
  Future<void> saveState(
    String userId,
    CloudArchiveKind kind,
    String key,
    CloudArchiveState state,
  ) async {
    final db = await appDatabase.database;
    await db.insert(DatabaseTables.cloudArchiveState, {
      'user_id': userId,
      'kind': kind.wireName,
      'record_key': key,
      'fingerprint': state.fingerprint,
      'server_revision': state.serverRevision,
      'pending_apply': state.pendingApply ? 1 : 0,
      'cloud_deleted': state.cloudDeleted ? 1 : 0,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<CloudArchiveCursor?> cursor(String userId) async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.syncState,
      where: 'user_id = ? AND entity_type = ?',
      whereArgs: [userId, _cursorEntity],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final at = rows.single['last_server_updated_at'] as String?;
    final id = rows.single['last_server_id'] as String?;
    if (at == null || id == null) return null;
    return CloudArchiveCursor(
      serverUpdatedAt: DateTime.parse(at).toUtc(),
      recordId: id,
    );
  }

  @override
  Future<void> saveCursor(String userId, CloudArchiveCursor cursor) async {
    final db = await appDatabase.database;
    await db.insert(DatabaseTables.syncState, {
      'user_id': userId,
      'entity_type': _cursorEntity,
      'last_server_updated_at': cursor.serverUpdatedAt
          .toUtc()
          .toIso8601String(),
      'last_server_id': cursor.recordId,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
