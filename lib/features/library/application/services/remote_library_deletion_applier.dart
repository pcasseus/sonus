import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../data/repositories/sqlite_library_deletion_ledger.dart';
import '../../data/repositories/sqlite_permanent_deletion_impact_repository.dart';
import '../../domain/deletion/permanent_deletion_impact.dart';
import 'duplicate_album_reconciliation_service.dart';
import 'permanent_deletion_service.dart';

/// The library_deletion archive record of one deletion or merge (App
/// Update 1.2): ids only, never names or counts.
abstract final class LibraryDeletionRecord {
  /// The payload published for journal row [journal] and its ledger rows.
  /// File paths are device-specific and are never published.
  static Map<String, Object?> payload({
    required Map<String, Object?> journal,
    required List<Map<String, Object?>> ledger,
    required Map<String, Object?> summary,
  }) => {
    'operation': journal['operation'],
    'targetType': journal['target_type'],
    'targetId': journal['target_id'],
    'committedAt': journal['committed_at'],
    'entries': [
      for (final row in ledger)
        if (row['entity_type'] != 'mediaFile')
          [row['entity_type'], row['entity_id']],
    ]..sort((a, b) => '${a[0]}:${a[1]}'.compareTo('${b[0]}:${b[1]}')),
    if (journal['operation'] == 'duplicateMerge')
      'remap': {
        for (final key in ['songs', 'editions', 'albums'])
          key: summary[key] ?? const {},
      },
  };
}

/// Applies another device's library_deletion record on this device, so a
/// deletion or merge made anywhere holds everywhere, including on a device
/// that connects later.
///
/// Idempotent: an operation already in the journal is not applied again.
/// Returns false, changing nothing, when this device does not yet have
/// what the operation depends on (for example a song another edition now
/// lists, whose new home has not arrived); it is applied on a later sync.
class RemoteLibraryDeletionApplier {
  RemoteLibraryDeletionApplier({
    required this.appDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase appDatabase;
  final DateTime Function() _now;

  Future<bool> apply(
    Transaction txn,
    String operationId,
    Map<String, Object?> payload,
  ) async {
    final known = await txn.query(
      DatabaseTables.libraryDeletionJournal,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [operationId],
    );
    if (known.isNotEmpty) return true;

    final entries = <String, Set<String>>{};
    for (final entry in (payload['entries'] as List? ?? const [])) {
      final pair = entry as List;
      (entries['${pair[0]}'] ??= {}).add('${pair[1]}');
    }

    return payload['operation'] == 'duplicateMerge'
        ? _merge(txn, operationId, payload)
        : _delete(txn, operationId, payload, entries);
  }

  Future<bool> _delete(
    Transaction txn,
    String operationId,
    Map<String, Object?> payload,
    Map<String, Set<String>> entries,
  ) async {
    final target = PermanentDeletionTarget.fromName(
      '${payload['targetType']}',
      '${payload['targetId']}',
    );
    final impact = await SqlitePermanentDeletionImpactRepository(txn)
        .planEntities(
          target: target,
          songs: entries['song'] ?? const {},
          albums: entries['album'] ?? const {},
          editions: entries['albumEdition'] ?? const {},
          artists: entries['artist'] ?? const {},
          sessions: entries['playbackSession'] ?? const {},
          plays: entries['qualifiedPlay'] ?? const {},
          momentKeys: entries['moment'] ?? const {},
        );

    // A song that stays (another edition lists it) but still has a
    // deleted edition as its home: wait for its new home to arrive.
    if (impact.editionIds.isNotEmpty) {
      final marks = List.filled(impact.editionIds.length, '?').join(', ');
      final homed = await txn.rawQuery(
        'SELECT id FROM ${DatabaseTables.songs} '
        'WHERE album_edition_id IN ($marks)',
        [...impact.editionIds],
      );
      if (homed.any((row) => !impact.songIds.contains(row['id']))) {
        return false;
      }
    }

    await PermanentDeletionService(
      appDatabase: appDatabase,
      now: _now,
      changes: LibraryChangeSignal(),
    ).applyRemote(txn, impact, operationId: operationId);

    // Everything the operation names is remembered here, including records
    // this device never had (a device that connects later), so no stale
    // copy, archive download or restored backup brings them back.
    final ledger = SqliteLibraryDeletionLedger(txn);
    for (final MapEntry(key: type, value: ids) in entries.entries) {
      final entity = DeletionLedgerEntity.values
          .where((e) => e.name == type && e != DeletionLedgerEntity.mediaFile)
          .firstOrNull;
      if (entity == null) continue;
      await ledger.record(
        entity,
        ids,
        reason: DeletionLedgerReason.userDeletion,
        operationId: operationId,
        at: _now(),
      );
    }
    return true;
  }

  Future<bool> _merge(
    Transaction txn,
    String operationId,
    Map<String, Object?> payload,
  ) async {
    final remap = (payload['remap'] as Map? ?? const {})
        .cast<String, Object?>();
    Map<String, String> mapOf(String key) =>
        (remap[key] as Map? ?? const {}).cast<String, String>();
    final songs = mapOf('songs');
    final editions = mapOf('editions');
    final albums = mapOf('albums');
    if (albums.length != 1) return true;
    final duplicateAlbumId = albums.keys.single;
    final keptAlbumId = albums.values.single;

    Future<bool> exists(String table, String id) async => (await txn.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    )).isNotEmpty;

    final service = DuplicateAlbumReconciliationService(
      appDatabase: appDatabase,
      now: _now,
      changes: LibraryChangeSignal(),
    );

    if (!await exists(DatabaseTables.albums, duplicateAlbumId)) {
      // Nothing of the duplicate here: only remember the merge.
      await service.recordRemoteMerge(
        txn,
        operationId: operationId,
        songs: songs,
        editions: editions,
        albums: albums,
      );
      return true;
    }
    // The kept release has not arrived here yet: wait for it.
    if (!await exists(DatabaseTables.albums, keptAlbumId)) return false;

    final pairs = <DuplicateSongPair>[];
    for (final MapEntry(key: duplicate, value: kept) in songs.entries) {
      if (!await exists(DatabaseTables.songs, duplicate)) continue;
      final keptRow = await txn.query(
        DatabaseTables.songs,
        columns: ['album_edition_id'],
        where: 'id = ?',
        whereArgs: [kept],
      );
      if (keptRow.isEmpty) return false;
      pairs.add(
        DuplicateSongPair(
          keptSongId: kept,
          keptEditionId: keptRow.single['album_edition_id']! as String,
          duplicateSongId: duplicate,
        ),
      );
    }
    // A song this device added to the duplicate since: not part of the
    // verified merge. Leave the merge for review here.
    final extra = await txn.query(
      DatabaseTables.songs,
      columns: ['id'],
      where: 'album_id = ?',
      whereArgs: [duplicateAlbumId],
    );
    if (extra.any((row) => !songs.containsKey(row['id']))) return false;

    final editionPairs = <DuplicateEditionPair>[];
    for (final MapEntry(key: duplicate, value: kept) in editions.entries) {
      if (!await exists(DatabaseTables.albumEditions, duplicate)) continue;
      if (!await exists(DatabaseTables.albumEditions, kept)) return false;
      editionPairs.add(
        DuplicateEditionPair(
          keptEditionId: kept,
          duplicateEditionId: duplicate,
        ),
      );
    }

    final movedPlays = await txn.query(
      DatabaseTables.qualifiedPlays,
      columns: ['id'],
      where: 'album_id = ?',
      whereArgs: [duplicateAlbumId],
    );
    await service.applyRemoteMerge(
      txn,
      DuplicateMerge(
        keptAlbumId: keptAlbumId,
        duplicateAlbumId: duplicateAlbumId,
        title: '',
        songPairs: pairs,
        editionPairs: editionPairs,
        movedPlayCount: movedPlays.length,
        movedLiveFileCount: 0,
      ),
      operationId: operationId,
    );
    return true;
  }
}
