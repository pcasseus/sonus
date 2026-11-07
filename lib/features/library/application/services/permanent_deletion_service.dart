import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../sync/data/daos/local_sync_dao.dart';
import '../../../sync/data/repositories/sqlite_local_sync_repository.dart';
import '../../../sync/domain/models/sync_data_contract.dart';
import '../../data/repositories/sqlite_library_deletion_ledger.dart';
import '../../data/repositories/sqlite_permanent_deletion_impact_repository.dart';
import '../../domain/deletion/permanent_deletion_impact.dart';

/// The preview the user confirmed no longer matches the library.
class StaleDeletionPreview implements Exception {
  const StaleDeletionPreview();

  @override
  String toString() =>
      'The library changed after the preview; nothing was deleted.';
}

/// The deletion is blocked; nothing was deleted.
class DeletionBlocked implements Exception {
  const DeletionBlocked(this.blockers);

  final Set<PermanentDeletionBlocker> blockers;

  @override
  String toString() => 'Deletion blocked: ${blockers.map((b) => b.name)}';
}

/// App Update 1.2: user-directed permanent deletion of a song, an edition,
/// a release or an artist, with its listening history ("a real history
/// wipe"). Never automatic, and distinct from duplicate merging, which
/// keeps history.
///
/// The user first sees [preview] (read-only). [delete] then runs in one
/// transaction: it plans again and refuses if the result differs from the
/// confirmed preview, so nothing beyond what was shown can be deleted. Any
/// failure rolls everything back.
///
/// What it does, in order:
/// - deletes the Moments about or naming the deleted records, or caused by
///   their plays (D5: surviving stories keep their numbers);
/// - deletes the stored weekly charts from the earliest affected week on;
///   they are rebuilt from the remaining plays when Charts next finalizes,
///   and those weeks publish no new Moments (D3, D5);
/// - deletes the listening history (sessions, segments, qualified plays);
/// - removes playlist entries, metadata provenance and artwork crops;
/// - removes the file links (never the audio files) and records the paths
///   so a rescan does not import them again;
/// - rehomes songs another edition still lists, then deletes the records;
/// - writes the deletion ledger and journal, and records cloud deletes.
///
/// While cloud sync is linked the deletion is blocked (D10, fail closed):
/// the cloud archive cannot yet delete the listening history it holds.
class PermanentDeletionService {
  PermanentDeletionService({
    required this.appDatabase,
    this.userId,
    Future<bool> Function(DatabaseExecutor db)? isCloudLinked,
    DateTime Function()? now,
    String Function()? generateOutboxId,
    String Function()? generateOperationId,
    LibraryChangeSignal? changes,
    this.onSongsDeleted,
  }) : _isCloudLinked = isCloudLinked ?? _accountLinked,
       _now = now ?? DateTime.now,
       _generateOutboxId = generateOutboxId ?? EntityId.syncOutbox,
       _generateOperationId = generateOperationId ?? EntityId.deletionOperation,
       _changes = changes ?? LibraryChangeSignal.shared;

  final AppDatabase appDatabase;
  final String? userId;

  /// Told the deleted song ids after commit (the play queue lives outside
  /// the database).
  final Future<void> Function(Set<String> songIds)? onSongsDeleted;

  final Future<bool> Function(DatabaseExecutor db) _isCloudLinked;
  final DateTime Function() _now;
  final String Function() _generateOutboxId;
  final String Function() _generateOperationId;
  final LibraryChangeSignal _changes;

  static Future<bool> _accountLinked(DatabaseExecutor db) async =>
      (await db.query(DatabaseTables.localAccountBinding, limit: 1)).isNotEmpty;

  /// What deleting [target] would remove. Read-only.
  Future<PermanentDeletionImpact> preview(
    PermanentDeletionTarget target, {
    PermanentDeletionOptions options = const PermanentDeletionOptions(),
  }) async {
    final db = await appDatabase.database;
    return _withLinkBlocker(
      db,
      await SqlitePermanentDeletionImpactRepository(
        db,
      ).plan(target, options: options),
    );
  }

  /// Deletes exactly what [confirmed] showed. Throws [StaleDeletionPreview]
  /// or [DeletionBlocked] with nothing changed.
  Future<PermanentDeletionImpact> delete(
    PermanentDeletionImpact confirmed, {
    PermanentDeletionOptions options = const PermanentDeletionOptions(),
  }) async {
    final impact = await appDatabase.transaction((txn) async {
      final current = await _withLinkBlocker(
        txn,
        await SqlitePermanentDeletionImpactRepository(
          txn,
        ).plan(confirmed.target, options: options),
      );
      if (!_sameScope(current, confirmed)) throw const StaleDeletionPreview();
      if (!current.canProceed) throw DeletionBlocked(current.blockers);
      await _execute(txn, current);
      return current;
    });

    _changes.notify(LibraryChangeKind.libraryEdited);
    if (impact.qualifiedPlayIds.isNotEmpty) {
      _changes.notify(LibraryChangeKind.listeningRecorded);
    }
    if (impact.songIds.isNotEmpty) await onSongsDeleted?.call(impact.songIds);
    return impact;
  }

  Future<PermanentDeletionImpact> _withLinkBlocker(
    DatabaseExecutor db,
    PermanentDeletionImpact impact,
  ) async {
    if (impact.blockers.contains(PermanentDeletionBlocker.notFound) ||
        !await _isCloudLinked(db)) {
      return impact;
    }
    return impact.withBlocker(PermanentDeletionBlocker.cloudSyncLinked);
  }

  static bool _sameScope(PermanentDeletionImpact a, PermanentDeletionImpact b) {
    bool same(Set<String> x, Set<String> y) =>
        x.length == y.length && x.containsAll(y);
    return a.target.kind == b.target.kind &&
        a.target.id == b.target.id &&
        same(a.songIds, b.songIds) &&
        same(a.albumIds, b.albumIds) &&
        same(a.editionIds, b.editionIds) &&
        same(a.artistIds, b.artistIds) &&
        same(a.songsKeptLosingListing, b.songsKeptLosingListing) &&
        same(a.playbackSessionIds, b.playbackSessionIds) &&
        same(a.qualifiedPlayIds, b.qualifiedPlayIds) &&
        same(a.chartEntryIds, b.chartEntryIds) &&
        same(a.allMomentIds, b.allMomentIds) &&
        same(a.affectedChartWeeks, b.affectedChartWeeks) &&
        same(a.artworkAssetIds, b.artworkAssetIds);
  }

  Future<void> _execute(Transaction txn, PermanentDeletionImpact impact) async {
    final timestamp = _now().toUtc();
    final stamp = timestamp.toIso8601String();
    final operationId = _generateOperationId();
    final ledger = SqliteLibraryDeletionLedger(txn);
    final sync = SqliteLocalSyncRepository(
      dao: LocalSyncDao(txn),
      generateId: _generateOutboxId,
      now: () => timestamp,
    );
    Future<void> ledgerAll(DeletionLedgerEntity entity, Iterable<String> ids) =>
        ledger.record(
          entity,
          ids,
          reason: DeletionLedgerReason.userDeletion,
          operationId: operationId,
          at: timestamp,
        );

    // 1. Moments (by id), remembered by their deduplication keys so the
    // cloud archive cannot return them.
    final momentKeys = <String>[];
    for (final id in impact.allMomentIds) {
      final rows = await txn.query(
        DatabaseTables.chartMomentEvents,
        columns: ['deduplication_key'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) continue;
      momentKeys.add(rows.single['deduplication_key']! as String);
      await txn.delete(
        DatabaseTables.chartMomentEvents,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await ledgerAll(DeletionLedgerEntity.moment, momentKeys);

    // 2. Stored weekly charts from the earliest affected week on, both
    // charts (D3). Entries cascade. Charts rebuilds them from the remaining
    // plays; the journal stops those weeks publishing new Moments.
    final rebuiltWeeks = <String>[];
    final from = impact.earliestAffectedWeekStartUtc;
    if (from != null) {
      final snapshots = await txn.query(
        DatabaseTables.chartSnapshots,
        columns: ['id', 'chart_type', 'week_start_utc'],
        where: 'week_start_utc >= ?',
        whereArgs: [from],
        orderBy: 'week_start_utc, chart_type',
      );
      for (final row in snapshots) {
        rebuiltWeeks.add('${row['chart_type']}:${row['week_start_utc']}');
        await txn.delete(
          DatabaseTables.chartSnapshots,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }

    // 3. Listening history. Segments and plays cascade from sessions.
    await _deleteIn(
      txn,
      DatabaseTables.playbackSessions,
      'id',
      impact.playbackSessionIds,
    );
    await _deleteIn(
      txn,
      DatabaseTables.qualifiedPlays,
      'id',
      impact.qualifiedPlayIds,
    );
    await ledgerAll(
      DeletionLedgerEntity.playbackSession,
      impact.playbackSessionIds,
    );
    await ledgerAll(
      DeletionLedgerEntity.qualifiedPlay,
      impact.qualifiedPlayIds,
    );

    // 4. Playlist entries, then each touched playlist is renumbered.
    await _deleteIn(
      txn,
      DatabaseTables.playlistItems,
      'song_id',
      impact.songIds,
    );
    for (final playlist in impact.playlists) {
      final rows = await txn.query(
        DatabaseTables.playlistItems,
        columns: ['id', 'position'],
        where: 'playlist_id = ?',
        whereArgs: [playlist.playlistId],
        orderBy: 'position ASC, created_at ASC, id ASC',
      );
      for (final (index, row) in rows.indexed) {
        if (row['position'] != index) {
          await txn.update(
            DatabaseTables.playlistItems,
            {'position': index},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }

    // 5. Edition only: songs another edition lists stay, homed there, and
    // their history follows them.
    final rehomedSongs = <String>{};
    final updatedEditions = <String>{};
    if (impact.target.kind == PermanentDeletionTargetKind.edition &&
        impact.editionIds.length == 1 &&
        impact.albumIds.isEmpty) {
      final editionId = impact.editionIds.single;
      for (final songId in impact.songsKeptLosingListing) {
        final song = (await txn.query(
          DatabaseTables.songs,
          columns: ['album_edition_id'],
          where: 'id = ?',
          whereArgs: [songId],
        )).single;
        var home = song['album_edition_id']! as String;
        if (home == editionId) {
          final listings = await txn.rawQuery(
            'SELECT t.album_edition_id AS id '
            'FROM ${DatabaseTables.albumEditionTracks} t '
            'JOIN ${DatabaseTables.albumEditions} e '
            'ON e.id = t.album_edition_id '
            'WHERE t.song_id = ? AND t.album_edition_id <> ? '
            'ORDER BY e.is_primary DESC, e.created_at, e.id',
            [songId, editionId],
          );
          home = listings.first['id']! as String;
          await txn.update(
            DatabaseTables.songs,
            {'album_edition_id': home, 'updated_at': stamp},
            where: 'id = ?',
            whereArgs: [songId],
          );
          rehomedSongs.add(songId);
        }
        for (final table in [
          DatabaseTables.playbackSessions,
          DatabaseTables.qualifiedPlays,
        ]) {
          await txn.update(
            table,
            {'album_edition_id': home},
            where: 'song_id = ? AND album_edition_id = ?',
            whereArgs: [songId, editionId],
          );
        }
      }
      // A primary edition hands the role to the edition listing the most
      // songs.
      final edition = (await txn.query(
        DatabaseTables.albumEditions,
        where: 'id = ?',
        whereArgs: [editionId],
      )).single;
      if (edition['is_primary'] == 1) {
        final next = await txn.rawQuery(
          'SELECT e.id FROM ${DatabaseTables.albumEditions} e '
          'LEFT JOIN ${DatabaseTables.albumEditionTracks} t '
          'ON t.album_edition_id = e.id '
          'WHERE e.album_id = ? AND e.id <> ? '
          'GROUP BY e.id ORDER BY COUNT(t.song_id) DESC, e.created_at, e.id '
          'LIMIT 1',
          [edition['album_id'], editionId],
        );
        final nextId = next.single['id']! as String;
        await txn.update(
          DatabaseTables.albumEditions,
          {'is_primary': 0, 'updated_at': stamp},
          where: 'id = ?',
          whereArgs: [editionId],
        );
        await txn.update(
          DatabaseTables.albumEditions,
          {'is_primary': 1, 'updated_at': stamp},
          where: 'id = ?',
          whereArgs: [nextId],
        );
        updatedEditions.add(nextId);
      }
    }

    // 6. Provenance and crops of everything deleted.
    for (final (type, ids) in [
      ('song', impact.songIds),
      ('album', impact.albumIds),
      ('albumEdition', impact.editionIds),
      ('artist', impact.artistIds),
    ]) {
      for (final id in ids) {
        await txn.delete(
          DatabaseTables.metadataFieldStates,
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [type, id],
        );
      }
    }
    for (final id in impact.editionIds) {
      await txn.delete(
        DatabaseTables.artworkCrops,
        where: "target_type = 'albumEdition' AND target_id = ?",
        whereArgs: [id],
      );
    }
    for (final id in impact.artistIds) {
      await txn.delete(
        DatabaseTables.artworkCrops,
        where:
            "target_type IN ('artistBanner', 'artistPortrait') "
            'AND target_id = ?',
        whereArgs: [id],
      );
    }

    // 7. File links (never the files). Their paths are remembered so a
    // rescan skips them until the user allows them back.
    final paths = <String>[];
    for (final songId in impact.songIds) {
      for (final row in await txn.query(
        DatabaseTables.mediaFileBindings,
        columns: ['normalized_path'],
        where: 'song_id = ?',
        whereArgs: [songId],
      )) {
        paths.add(row['normalized_path']! as String);
      }
    }
    await _deleteIn(
      txn,
      DatabaseTables.mediaFileBindings,
      'song_id',
      impact.songIds,
    );
    await ledgerAll(DeletionLedgerEntity.mediaFile, paths);

    // 8. The records. Credits, listings, lyrics and import reviews cascade
    // from songs; classifications and project rows from albums; credits on
    // other artists' songs keep their printed name (SET NULL).
    await _deleteIn(txn, DatabaseTables.songs, 'id', impact.songIds);
    await _deleteIn(txn, DatabaseTables.albumEditions, 'id', impact.editionIds);
    await _deleteIn(txn, DatabaseTables.albums, 'id', impact.albumIds);
    await _deleteIn(txn, DatabaseTables.artists, 'id', impact.artistIds);
    // Artwork nothing else uses (the image files themselves are app cache,
    // not the user's music).
    await _deleteIn(
      txn,
      DatabaseTables.artworkAssets,
      'id',
      impact.artworkAssetIds,
    );

    await ledgerAll(DeletionLedgerEntity.song, impact.songIds);
    await ledgerAll(DeletionLedgerEntity.albumEdition, impact.editionIds);
    await ledgerAll(DeletionLedgerEntity.album, impact.albumIds);
    await ledgerAll(DeletionLedgerEntity.artist, impact.artistIds);

    // 9. Cloud: deletes for what the cloud has seen; changed songs and
    // editions that stay are sent again.
    for (final (entity, ids) in [
      (CloudDataEntity.song, impact.songIds),
      (CloudDataEntity.albumEdition, impact.editionIds),
      (CloudDataEntity.album, impact.albumIds),
      (CloudDataEntity.artist, impact.artistIds),
      (CloudDataEntity.artworkAsset, impact.artworkAssetIds),
    ]) {
      for (final id in ids) {
        final known = await txn.query(
          'sync_cloud_revision_baselines',
          columns: ['entity_id'],
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [entity.name, id],
          limit: 1,
        );
        if (known.isNotEmpty) {
          await sync.recordDelete(
            userId: userId,
            entityType: entity,
            entityId: id,
          );
        } else {
          await txn.delete(
            DatabaseTables.syncOutbox,
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: [entity.name, id],
          );
        }
      }
    }
    for (final id in {...rehomedSongs, ...impact.collaborationSongIdsKept}) {
      await sync.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.song,
        entityId: id,
      );
    }
    for (final id in updatedEditions) {
      await sync.recordUpsert(
        userId: userId,
        entityType: CloudDataEntity.albumEdition,
        entityId: id,
      );
    }

    // 10. The journal: the Moments cutoff and the recalculated weeks.
    await txn.insert(DatabaseTables.libraryDeletionJournal, {
      'id': operationId,
      'operation': DeletionLedgerReason.userDeletion.name,
      'target_type': impact.target.kind.name,
      'target_id': impact.target.id,
      'rebuilt_weeks': jsonEncode(rebuiltWeeks),
      'summary': jsonEncode({
        'songs': impact.songIds.length,
        'albums': impact.albumIds.length,
        'editions': impact.editionIds.length,
        'artists': impact.artistIds.length,
        'sessions': impact.playbackSessionIds.length,
        'plays': impact.qualifiedPlayIds.length,
        'moments': momentKeys.length,
        'files': paths.length,
      }),
      'committed_at': stamp,
    });
  }

  static Future<void> _deleteIn(
    Transaction txn,
    String table,
    String column,
    Set<String> ids,
  ) async {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final part = list.sublist(i, (i + 400).clamp(0, list.length));
      await txn.delete(
        table,
        where: '$column IN (${List.filled(part.length, '?').join(', ')})',
        whereArgs: part,
      );
    }
  }
}
