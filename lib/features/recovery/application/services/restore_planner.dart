import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../models/backup_table_coverage.dart';
import '../models/restore_plan.dart';
import 'backup_archive_verifier.dart';

/// Describes what replacing local portable data with a backup would change.
///
/// Read-only: it never modifies the local database or any file.
class RestorePlanner {
  const RestorePlanner({required this.appDatabase});

  final AppDatabase appDatabase;

  // Device-local artwork columns; they always differ across devices and are
  // rewritten during restore, so they do not count as content changes.
  static const _deviceLocalArtworkColumns = {'file_path', 'normalized_path'};

  /// Primary-key columns of [table], in key order, from the live schema.
  static Future<List<String>> primaryKeyColumns(
    DatabaseExecutor executor,
    String table,
  ) async {
    // Table names originate from the trusted coverage contract.
    final columns = await executor.rawQuery('PRAGMA table_info("$table")');

    final keyed = [
      for (final column in columns)
        if ((column['pk'] as int) > 0) column,
    ]..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));

    if (keyed.isEmpty) {
      throw FormatException('Portable table $table has no primary key.');
    }

    return [for (final column in keyed) column['name'] as String];
  }

  static String rowKey(Map<String, Object?> row, List<String> keyColumns) =>
      jsonEncode([for (final column in keyColumns) row[column]]);

  Future<RestorePlan> plan(VerifiedBackupContents contents) async {
    final payload = contents.backup.payload;
    final database = await appDatabase.database;

    final snapshot = await database.transaction((transaction) async {
      final changes = <RestoreTableChange>[];
      var localRows = 0;

      for (final coverage in BackupCoverageContract.portableTables) {
        final table = coverage.table;

        // An older backup without an optional table leaves it unchanged.
        if (!payload.tables.containsKey(table)) continue;

        final keyColumns = await primaryKeyColumns(transaction, table);
        final local = await transaction.query(table);
        localRows += local.length;

        final localByKey = {
          for (final row in local) rowKey(row, keyColumns): row,
        };

        final ignored = table == DatabaseTables.artworkAssets
            ? _deviceLocalArtworkColumns
            : const <String>{};

        var added = 0;
        var updated = 0;
        var unchanged = 0;
        final backupKeys = <String>{};

        for (final row in payload.tables[table]!) {
          final key = rowKey(row, keyColumns);

          if (!backupKeys.add(key)) {
            throw FormatException('Duplicate primary key in backup $table.');
          }

          final existing = localByKey[key];

          if (existing == null) {
            added++;
          } else if (_sameContent(existing, row, ignored)) {
            unchanged++;
          } else {
            updated++;
          }
        }

        changes.add(
          RestoreTableChange(
            table: table,
            added: added,
            updated: updated,
            unchanged: unchanged,
            removed: localByKey.keys
                .where((k) => !backupKeys.contains(k))
                .length,
          ),
        );
      }

      return (
        changes: changes,
        localRows: localRows,
        bindings: await transaction.query(
          DatabaseTables.mediaFileBindings,
          columns: ['song_id', 'is_available'],
        ),
        reviews: await transaction.query(
          DatabaseTables.songImportReviews,
          columns: ['song_id'],
        ),
        localArtwork: await transaction.query(
          DatabaseTables.artworkAssets,
          columns: ['id', 'file_path'],
        ),
      );
    });

    final backupSongIds = {
      for (final row in payload.tables[DatabaseTables.songs]!)
        row['id'] as String,
    };

    var bindingsKept = 0;
    final songsWithAudio = <String>{};

    for (final binding in snapshot.bindings) {
      final songId = binding['song_id'] as String;

      if (backupSongIds.contains(songId)) {
        bindingsKept++;

        if (binding['is_available'] == 1) {
          songsWithAudio.add(songId);
        }
      }
    }

    final reviewsKept = snapshot.reviews
        .where((row) => backupSongIds.contains(row['song_id']))
        .length;

    final localArtworkPaths = {
      for (final row in snapshot.localArtwork)
        row['id'] as String: row['file_path'] as String,
    };

    var artworkReused = 0;

    for (final artwork in contents.artwork) {
      final localPath = localArtworkPaths[artwork.artworkId];

      if (localPath != null &&
          await isIdenticalLocalArtwork(
            localPath,
            byteLength: artwork.byteLength,
            sha256Digest: artwork.sha256Digest,
          )) {
        artworkReused++;
      }
    }

    return RestorePlan(
      backupId: contents.backup.manifest.backupId,
      tables: snapshot.changes,
      localPortableRowCount: snapshot.localRows,
      deviceImpact: RestoreDeviceImpact(
        mediaBindingsKept: bindingsKept,
        mediaBindingsRemoved: snapshot.bindings.length - bindingsKept,
        importReviewsKept: reviewsKept,
        importReviewsRemoved: snapshot.reviews.length - reviewsKept,
        songsWithoutAudio: backupSongIds.length - songsWithAudio.length,
        artworkReused: artworkReused,
        artworkInstalled: contents.artwork.length - artworkReused,
      ),
    );
  }

  /// Whether a local artwork file already holds exactly the backup bytes.
  static Future<bool> isIdenticalLocalArtwork(
    String filePath, {
    required int byteLength,
    required String sha256Digest,
  }) async {
    final file = File(filePath);

    if (await FileSystemEntity.type(filePath, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != byteLength) {
      return false;
    }

    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == sha256Digest;
  }

  bool _sameContent(
    Map<String, Object?> local,
    Map<String, Object?> backup,
    Set<String> ignored,
  ) {
    for (final entry in backup.entries) {
      if (ignored.contains(entry.key)) continue;
      if (local[entry.key] != entry.value) return false;
    }

    return local.length == backup.length;
  }
}
