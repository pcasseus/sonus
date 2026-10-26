import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../models/backup_table_coverage.dart';
import 'backup_json_codec.dart';
import 'restore_planner.dart';

enum RestorePhase {
  clearDependentTables,
  removeReplacedArtwork,
  upsertAnchors,
  removeAnchorsNotInBackup,
  insertDependentTables,
  verifyIntegrity,
}

class RestoreIntegrityFailure implements Exception {
  const RestoreIntegrityFailure(this.message);

  final String message;

  @override
  String toString() => 'RestoreIntegrityFailure: $message';
}

/// Replaces local portable data with a decoded backup.
///
/// Must run inside a single transaction supplied by the caller; any
/// exception rolls every change back.
///
/// * Anchor tables (artwork, artists, albums, editions, songs) are updated
///   in place by primary key, so device-local rows that depend on a
///   surviving song (audio bindings, import reviews) are never cascaded
///   away.
/// * Dependent portable tables are cleared and reinserted verbatim, which
///   preserves every identity and value.
/// * Device-local and sync tables are never written, except removing the
///   audio bindings of songs that are not in the backup (required by the
///   RESTRICT foreign key).
class SqliteRestoreExecutor {
  const SqliteRestoreExecutor({this.afterPhase});

  /// Test seam invoked after each phase, inside the transaction.
  final Future<void> Function(RestorePhase phase)? afterPhase;

  /// Parents first.
  static const anchorTables = [
    DatabaseTables.artworkAssets,
    DatabaseTables.artists,
    DatabaseTables.albums,
    DatabaseTables.albumEditions,
    DatabaseTables.songs,
  ];

  /// Parents first; deletion runs in reverse.
  static const dependentTables = [
    DatabaseTables.metadataFieldStates,
    DatabaseTables.albumEditionTracks,
    DatabaseTables.songArtistCredits,
    DatabaseTables.trackLyrics,
    DatabaseTables.playbackSessions,
    DatabaseTables.playbackListeningSegments,
    DatabaseTables.qualifiedPlays,
    DatabaseTables.chartSnapshots,
    DatabaseTables.chartEntries,
    DatabaseTables.chartMomentEvents,
    DatabaseTables.playlists,
    DatabaseTables.playlistItems,
  ];

  /// Portable tables older backups may lack. Restored like dependent tables
  /// when the backup has them; otherwise their local rows are untouched.
  static const optionalTables = [
    DatabaseTables.albumReleaseClassifications,
    DatabaseTables.artistProjectAssignments,
    DatabaseTables.artworkCrops,
  ];

  Future<void> apply({
    required Transaction transaction,
    required DecodedBackup backup,
    required Map<String, String> artworkPaths,
  }) async {
    _assertCoverage();

    final tables = backup.payload.tables;
    final keys = <String, List<String>>{
      for (final coverage in BackupCoverageContract.portableTables)
        coverage.table: await RestorePlanner.primaryKeyColumns(
          transaction,
          coverage.table,
        ),
    };

    final artworkRows = [
      for (final row in tables[DatabaseTables.artworkAssets]!)
        _remapArtwork(row, artworkPaths),
    ];

    final restoredOptional = [
      for (final table in optionalTables)
        if (tables.containsKey(table)) table,
    ];

    // 1. Dependent tables reference anchors; clear them children first.
    for (final table in [...dependentTables, ...restoredOptional].reversed) {
      await transaction.delete(table);
    }
    await afterPhase?.call(RestorePhase.clearDependentTables);

    // 2. Artwork not in the backup. References become NULL and are
    // rewritten by step 3; removing first also frees unique paths.
    await _deleteMissing(
      transaction,
      DatabaseTables.artworkAssets,
      keys[DatabaseTables.artworkAssets]!,
      artworkRows,
    );
    await afterPhase?.call(RestorePhase.removeReplacedArtwork);

    // 3. Update or insert anchors, parents first.
    for (final table in anchorTables) {
      final rows = table == DatabaseTables.artworkAssets
          ? artworkRows
          : tables[table]!;

      for (final row in rows) {
        await _updateOrInsert(transaction, table, keys[table]!, row);
      }
    }
    await afterPhase?.call(RestorePhase.upsertAnchors);

    // 4. Anchors not in the backup, children first. Audio bindings of
    // departing songs must go first because of ON DELETE RESTRICT.
    final departingSongs = await _missingKeys(
      transaction,
      DatabaseTables.songs,
      keys[DatabaseTables.songs]!,
      tables[DatabaseTables.songs]!,
    );

    for (final songKey in departingSongs) {
      await transaction.delete(
        DatabaseTables.mediaFileBindings,
        where: 'song_id = ?',
        whereArgs: [songKey.single],
      );
    }

    for (final table in anchorTables.reversed) {
      if (table == DatabaseTables.artworkAssets) continue;

      await _deleteMissing(transaction, table, keys[table]!, tables[table]!);
    }
    await afterPhase?.call(RestorePhase.removeAnchorsNotInBackup);

    // 5. Dependent rows, verbatim, parents first.
    for (final table in [...dependentTables, ...restoredOptional]) {
      final batch = transaction.batch();

      for (final row in tables[table]!) {
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      await batch.commit(noResult: true);
    }
    await afterPhase?.call(RestorePhase.insertDependentTables);

    // 6. Verify before the transaction may commit.
    await _verify(transaction, backup, artworkRows);
    await afterPhase?.call(RestorePhase.verifyIntegrity);
  }

  void _assertCoverage() {
    final handled = {...anchorTables, ...dependentTables, ...optionalTables};
    final portable = {
      for (final coverage in BackupCoverageContract.portableTables)
        coverage.table,
    };

    if (handled.length != portable.length || !handled.containsAll(portable)) {
      throw StateError('Restore does not cover every portable table.');
    }
  }

  Map<String, Object?> _remapArtwork(
    Map<String, Object?> row,
    Map<String, String> artworkPaths,
  ) {
    final id = row['id'] as String;
    final devicePath = artworkPaths[id];

    if (devicePath == null) {
      throw RestoreIntegrityFailure('No installed file for artwork $id.');
    }

    return {
      ...row,
      'file_path': devicePath,
      'normalized_path': TextNormalizer.normalizePath(devicePath),
    };
  }

  Future<void> _updateOrInsert(
    Transaction transaction,
    String table,
    List<String> keyColumns,
    Map<String, Object?> row,
  ) async {
    final where = keyColumns.map((column) => '"$column" = ?').join(' AND ');
    final whereArgs = [for (final column in keyColumns) row[column]];
    final values = {
      for (final entry in row.entries)
        if (!keyColumns.contains(entry.key)) entry.key: entry.value,
    };

    // UPDATE never cascades on non-key columns; INSERT handles new rows.
    final updated = values.isEmpty
        ? (await transaction.query(
            table,
            where: where,
            whereArgs: whereArgs,
          )).length
        : await transaction.update(
            table,
            values,
            where: where,
            whereArgs: whereArgs,
          );

    if (updated == 0) {
      await transaction.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<List<List<Object?>>> _missingKeys(
    Transaction transaction,
    String table,
    List<String> keyColumns,
    List<Map<String, Object?>> backupRows,
  ) async {
    final wanted = {
      for (final row in backupRows) RestorePlanner.rowKey(row, keyColumns),
    };

    final local = await transaction.query(table, columns: keyColumns);

    return [
      for (final row in local)
        if (!wanted.contains(RestorePlanner.rowKey(row, keyColumns)))
          [for (final column in keyColumns) row[column]],
    ];
  }

  Future<void> _deleteMissing(
    Transaction transaction,
    String table,
    List<String> keyColumns,
    List<Map<String, Object?>> backupRows,
  ) async {
    final where = keyColumns.map((column) => '"$column" = ?').join(' AND ');

    for (final key in await _missingKeys(
      transaction,
      table,
      keyColumns,
      backupRows,
    )) {
      await transaction.delete(table, where: where, whereArgs: key);
    }
  }

  Future<void> _verify(
    Transaction transaction,
    DecodedBackup backup,
    List<Map<String, Object?>> artworkRows,
  ) async {
    for (final entry in backup.manifest.rowCounts.entries) {
      final rows = await transaction.rawQuery(
        'SELECT COUNT(*) AS c FROM "${entry.key}"',
      );

      if (rows.single['c'] != entry.value) {
        throw RestoreIntegrityFailure('Row count mismatch in ${entry.key}.');
      }
    }

    final foreignKeyViolations = await transaction.rawQuery(
      'PRAGMA foreign_key_check',
    );

    if (foreignKeyViolations.isNotEmpty) {
      throw const RestoreIntegrityFailure('Foreign key violations found.');
    }

    final integrity = await transaction.rawQuery('PRAGMA quick_check');

    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const RestoreIntegrityFailure('SQLite integrity check failed.');
    }

    final version = await transaction.rawQuery('PRAGMA user_version');

    if (version.single['user_version'] != AppDatabase.databaseVersion) {
      throw const RestoreIntegrityFailure('Database version changed.');
    }

    for (final row in artworkRows) {
      final stored = await transaction.query(
        DatabaseTables.artworkAssets,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [row['id']],
      );

      if (stored.length != 1 ||
          stored.single['file_path'] != row['file_path']) {
        throw const RestoreIntegrityFailure('Artwork path remapping failed.');
      }
    }
  }
}
