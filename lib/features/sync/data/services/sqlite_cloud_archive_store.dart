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
        final items = [
          for (final item in (payload['items'] as List? ?? const []))
            Map<String, Object?>.from(item as Map),
        ];
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
        await _insert(
          txn,
          DatabaseTables.playbackSessions,
          session,
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
        final play = payload['qualified_play'];
        if (play is Map) {
          await _insert(
            txn,
            DatabaseTables.qualifiedPlays,
            Map<String, Object?>.from(play),
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
        await _insert(
          txn,
          _tables[record.kind]!,
          payload,
          ConflictAlgorithm.ignore,
        );
    }
    return CloudArchiveApplyOutcome.applied;
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
