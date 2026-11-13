import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';

/// What kind of record a ledger row names. The names are stored.
enum DeletionLedgerEntity {
  artist,
  album,
  albumEdition,
  song,
  playbackSession,
  qualifiedPlay,
  moment,

  /// A file path (normalized) the user deleted from the library. A rescan
  /// skips it until the user allows it back.
  mediaFile,
}

enum DeletionLedgerReason { userDeletion, duplicateMerge }

/// The App Update 1.2 deletion ledger (DeletionSchema): records this device
/// deleted on purpose, so stale cloud data, an archive download, an older
/// backup or a rescan never brings them back.
///
/// Ids and paths only, never names or counts.
class SqliteLibraryDeletionLedger {
  const SqliteLibraryDeletionLedger(this._db);

  final DatabaseExecutor _db;

  static const int _chunk = 400;

  Future<void> record(
    DeletionLedgerEntity entity,
    Iterable<String> ids, {
    required DeletionLedgerReason reason,
    required String operationId,
    required DateTime at,
  }) async {
    final stamp = at.toUtc().toIso8601String();
    for (final id in ids) {
      await _db.rawInsert(
        'INSERT OR IGNORE INTO ${DatabaseTables.libraryDeletionLedger} '
        '(entity_type, entity_id, reason, operation_id, recorded_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [entity.name, id, reason.name, operationId, stamp],
      );
    }
  }

  Future<bool> contains(DeletionLedgerEntity entity, String? id) async {
    if (id == null || id.isEmpty) return false;
    final rows = await _db.query(
      DatabaseTables.libraryDeletionLedger,
      columns: ['entity_id'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entity.name, id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Whether [id] was deleted by the user (not merged into another record).
  Future<bool> deletedByUser(DeletionLedgerEntity entity, String? id) async {
    if (id == null || id.isEmpty) return false;
    final rows = await _db.query(
      DatabaseTables.libraryDeletionLedger,
      columns: ['entity_id'],
      where: 'entity_type = ? AND entity_id = ? AND reason = ?',
      whereArgs: [entity.name, id, DeletionLedgerReason.userDeletion.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Whether any of [ids] was deleted by the user. Given a merge chain (a
  /// duplicate, then each record it was merged into), this tells whether
  /// the record the duplicate became was deleted later.
  Future<bool> anyDeletedByUser(
    DeletionLedgerEntity entity,
    Iterable<String> ids,
  ) async {
    for (final id in ids) {
      if (await deletedByUser(entity, id)) return true;
    }
    return false;
  }

  /// The subset of [ids] that is in the ledger.
  Future<Set<String>> ledgered(
    DeletionLedgerEntity entity,
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    final out = <String>{};
    for (var i = 0; i < list.length; i += _chunk) {
      final part = list.sublist(i, (i + _chunk).clamp(0, list.length));
      final marks = List.filled(part.length, '?').join(', ');
      for (final row in await _db.rawQuery(
        'SELECT entity_id FROM ${DatabaseTables.libraryDeletionLedger} '
        'WHERE entity_type = ? AND entity_id IN ($marks)',
        [entity.name, ...part],
      )) {
        out.add(row['entity_id']! as String);
      }
    }
    return out;
  }

  /// Lets a deleted file be imported again (it becomes a new song with no
  /// history).
  Future<void> allowFile(String normalizedPath) => _db.delete(
    DatabaseTables.libraryDeletionLedger,
    where: 'entity_type = ? AND entity_id = ?',
    whereArgs: [DeletionLedgerEntity.mediaFile.name, normalizedPath],
  );
}
