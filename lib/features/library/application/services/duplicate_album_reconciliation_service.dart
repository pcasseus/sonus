import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../../core/identity/text_normalizer.dart';
import '../../../import/application/identity/recording_evidence.dart';
import '../../data/repositories/sqlite_library_deletion_ledger.dart';
import '../../../sync/data/daos/local_sync_dao.dart';
import '../../../sync/data/repositories/sqlite_local_sync_repository.dart';
import '../../../sync/domain/models/sync_data_contract.dart';

/// App Update 1.2: verified duplicate releases are merged into one.
///
/// Two albums are the **same release** only when all of these hold:
/// - the same owner (artist id) and canonical title;
/// - the same editions (type and title);
/// - every song pairs one-to-one with a song of the other album: the same
///   title, version, primary artist, featured artists, disc and track
///   number, and known durations within RecordingEvidence's tolerance;
/// - compatible release dates (equal, the same year at a lower precision,
///   or unknown on one side).
/// Titles or folders alone never verify anything.
///
/// The **canonical** album is the one with the most listening, then the most
/// Moments, then the most curated metadata, then the oldest. It keeps its
/// ids, artwork, release date and history. Each duplicate song's playable
/// file links, listening history, playlist entries and lyrics move to its
/// pair; the duplicate's library records are then deleted, with cloud
/// deletes recorded. No audio file is touched, and no play is copied, so
/// nothing is counted twice.
///
/// A duplicate that has stored weekly chart rows or Moments is **not**
/// merged automatically (merging would rewrite published chart history):
/// it is reported for review.
///
/// This is not user-directed permanent deletion. It never deletes listening
/// history; it moves it to the record that stays.
class DuplicateAlbumReconciliationService {
  DuplicateAlbumReconciliationService({
    required this.appDatabase,
    this.userId,
    DateTime Function()? now,
    String Function()? generateOutboxId,
    String Function()? generateOperationId,
    LibraryChangeSignal? changes,
  }) : _now = now ?? DateTime.now,
       _generateOutboxId = generateOutboxId ?? EntityId.syncOutbox,
       _generateOperationId = generateOperationId ?? EntityId.deletionOperation,
       _changes = changes ?? LibraryChangeSignal.shared;

  final AppDatabase appDatabase;

  /// The signed-in sync user, if any, for the recorded cloud changes.
  final String? userId;

  final DateTime Function() _now;
  final String Function() _generateOutboxId;
  final String Function() _generateOperationId;
  final LibraryChangeSignal _changes;

  /// What a reconciliation would do now. Read-only.
  Future<DuplicateReconciliationPlan> plan({DatabaseExecutor? executor}) async {
    final db = executor ?? await appDatabase.database;
    return _DuplicatePlanner(db).plan();
  }

  /// Merges every verified duplicate, each group in one transaction.
  ///
  /// When [approved] is given, each group is merged only if planning again
  /// inside its transaction gives the same merge; otherwise that group is
  /// left untouched and reported as stale.
  Future<DuplicateReconciliationReport> reconcile({
    DuplicateReconciliationPlan? approved,
  }) async {
    final initial = approved ?? await plan();
    final merged = <DuplicateMerge>[];
    final stale = <DuplicateMerge>[];

    for (final merge in initial.merges) {
      final applied = await appDatabase.transaction((txn) async {
        final current = await _DuplicatePlanner(txn).plan();
        final same = current.merges.any((m) => m.sameAs(merge));
        if (!same) return false;
        await _apply(txn, merge);
        return true;
      });
      (applied ? merged : stale).add(merge);
    }

    if (merged.isNotEmpty) {
      _changes.notify(LibraryChangeKind.libraryEdited);
      if (merged.any((m) => m.movedPlayCount > 0)) {
        _changes.notify(LibraryChangeKind.listeningRecorded);
      }
    }

    return DuplicateReconciliationReport(
      merged: merged,
      stale: stale,
      reviews: initial.reviews,
    );
  }

  Future<void> _apply(Transaction txn, DuplicateMerge merge) async {
    final timestamp = _now();
    final stamp = timestamp.toUtc().toIso8601String();
    final sync = SqliteLocalSyncRepository(
      dao: LocalSyncDao(txn),
      generateId: _generateOutboxId,
      now: () => timestamp,
    );
    final touchedPlaylists = <String>{};

    for (final pair in merge.songPairs) {
      final keep = pair.keptSongId;
      final drop = pair.duplicateSongId;

      // File links: keep every playable one; when none plays, keep the most
      // recently seen. Superseded rows are only forgotten locations: the
      // files themselves are never touched.
      final bindings = await txn.query(
        DatabaseTables.mediaFileBindings,
        where: 'song_id IN (?, ?)',
        whereArgs: [keep, drop],
        orderBy: 'last_seen_at DESC, updated_at DESC, id ASC',
      );
      final live = bindings.where((b) => b['is_available'] == 1).toList();
      final kept = live.isNotEmpty ? live : bindings.take(1).toList();
      final keptIds = {for (final b in kept) b['id']};
      for (final binding in bindings) {
        if (!keptIds.contains(binding['id'])) {
          await txn.delete(
            DatabaseTables.mediaFileBindings,
            where: 'id = ?',
            whereArgs: [binding['id']],
          );
        } else if (binding['song_id'] == drop) {
          await txn.update(
            DatabaseTables.mediaFileBindings,
            {'song_id': keep, 'updated_at': stamp},
            where: 'id = ?',
            whereArgs: [binding['id']],
          );
        }
      }

      // Listening history follows the recording; nothing is duplicated.
      for (final table in [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
      ]) {
        await txn.update(
          table,
          {
            'song_id': keep,
            'album_id': merge.keptAlbumId,
            'album_edition_id': pair.keptEditionId,
          },
          where: 'song_id = ?',
          whereArgs: [drop],
        );
      }

      // Playlists: the kept song takes the duplicate's place, once.
      final items = await txn.query(
        DatabaseTables.playlistItems,
        where: 'song_id = ?',
        whereArgs: [drop],
      );
      for (final item in items) {
        final playlistId = item['playlist_id']! as String;
        touchedPlaylists.add(playlistId);
        final already = await txn.query(
          DatabaseTables.playlistItems,
          columns: ['id'],
          where: 'playlist_id = ? AND song_id = ?',
          whereArgs: [playlistId, keep],
        );
        if (already.isEmpty) {
          await txn.update(
            DatabaseTables.playlistItems,
            {'song_id': keep, 'updated_at': stamp},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        } else {
          await txn.delete(
            DatabaseTables.playlistItems,
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }

      // Lyrics: the kept song's own win; otherwise the duplicate's move.
      final keptLyrics = await txn.query(
        DatabaseTables.trackLyrics,
        columns: ['song_id'],
        where: 'song_id = ?',
        whereArgs: [keep],
      );
      if (keptLyrics.isEmpty) {
        await txn.update(
          DatabaseTables.trackLyrics,
          {'song_id': keep},
          where: 'song_id = ?',
          whereArgs: [drop],
        );
      }
    }

    for (final playlistId in touchedPlaylists) {
      final rows = await txn.query(
        DatabaseTables.playlistItems,
        columns: ['id', 'position'],
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
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

    // Edition details the kept edition lacks (it keeps its own otherwise).
    for (final pair in merge.editionPairs) {
      final kept = (await txn.query(
        DatabaseTables.albumEditions,
        where: 'id = ?',
        whereArgs: [pair.keptEditionId],
      )).single;
      final duplicate = (await txn.query(
        DatabaseTables.albumEditions,
        where: 'id = ?',
        whereArgs: [pair.duplicateEditionId],
      )).single;
      final fill = <String, Object?>{};
      if (kept['artwork_id'] == null && duplicate['artwork_id'] != null) {
        fill['artwork_id'] = duplicate['artwork_id'];
      }
      if (kept['release_date'] == null && duplicate['release_date'] != null) {
        fill['release_date'] = duplicate['release_date'];
        fill['release_date_precision'] = duplicate['release_date_precision'];
      }
      if (kept['genre'] == null && duplicate['genre'] != null) {
        fill['genre'] = duplicate['genre'];
      }
      if (fill.isNotEmpty) {
        await txn.update(
          DatabaseTables.albumEditions,
          {...fill, 'updated_at': stamp},
          where: 'id = ?',
          whereArgs: [pair.keptEditionId],
        );
        await sync.recordUpsert(
          userId: userId,
          entityType: CloudDataEntity.albumEdition,
          entityId: pair.keptEditionId,
        );
      }

      final keptCrop = await txn.query(
        DatabaseTables.artworkCrops,
        columns: ['target_id'],
        where: "target_type = 'albumEdition' AND target_id = ?",
        whereArgs: [pair.keptEditionId],
      );
      if (keptCrop.isEmpty && fill.containsKey('artwork_id')) {
        await txn.update(
          DatabaseTables.artworkCrops,
          {'target_id': pair.keptEditionId},
          where: "target_type = 'albumEdition' AND target_id = ?",
          whereArgs: [pair.duplicateEditionId],
        );
      }
      await txn.delete(
        DatabaseTables.artworkCrops,
        where: "target_type = 'albumEdition' AND target_id = ?",
        whereArgs: [pair.duplicateEditionId],
      );
    }

    // Release-level organisation follows the kept album.
    final keptClassification = await txn.query(
      DatabaseTables.albumReleaseClassifications,
      columns: ['album_id'],
      where: 'album_id = ?',
      whereArgs: [merge.keptAlbumId],
    );
    if (keptClassification.isEmpty) {
      await txn.update(
        DatabaseTables.albumReleaseClassifications,
        {'album_id': merge.keptAlbumId},
        where: 'album_id = ?',
        whereArgs: [merge.duplicateAlbumId],
      );
    }
    await txn.update(
      DatabaseTables.artistProjectAssignments,
      {'album_id': merge.keptAlbumId},
      where: 'album_id = ?',
      whereArgs: [merge.duplicateAlbumId],
    );
    // Orphaned history that still names the duplicate release.
    for (final table in [
      DatabaseTables.playbackSessions,
      DatabaseTables.qualifiedPlays,
    ]) {
      await txn.update(
        table,
        {'album_id': merge.keptAlbumId},
        where: 'album_id = ?',
        whereArgs: [merge.duplicateAlbumId],
      );
    }

    // The duplicate's own records go. Cascades remove its credits, edition
    // listings, import reviews and leftover lyrics.
    final duplicateSongIds = [
      for (final p in merge.songPairs) p.duplicateSongId,
    ];
    final duplicateEditionIds = [
      for (final p in merge.editionPairs) p.duplicateEditionId,
    ];
    for (final (type, ids) in [
      ('song', duplicateSongIds),
      ('albumEdition', duplicateEditionIds),
      ('album', [merge.duplicateAlbumId]),
    ]) {
      for (final id in ids) {
        await txn.delete(
          DatabaseTables.metadataFieldStates,
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [type, id],
        );
      }
    }
    for (final id in duplicateSongIds) {
      await txn.delete(DatabaseTables.songs, where: 'id = ?', whereArgs: [id]);
    }
    for (final id in duplicateEditionIds) {
      await txn.delete(
        DatabaseTables.albumEditions,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await txn.delete(
      DatabaseTables.albums,
      where: 'id = ?',
      whereArgs: [merge.duplicateAlbumId],
    );

    // The ledger keeps the merged duplicates from coming back (stale cloud
    // copies, an older backup), and the journal remembers where they went,
    // so history in an older backup follows the kept records.
    final operationId = _generateOperationId();
    final ledger = SqliteLibraryDeletionLedger(txn);
    for (final (entity, ids) in [
      (DeletionLedgerEntity.song, duplicateSongIds),
      (DeletionLedgerEntity.albumEdition, duplicateEditionIds),
      (DeletionLedgerEntity.album, [merge.duplicateAlbumId]),
    ]) {
      await ledger.record(
        entity,
        ids,
        reason: DeletionLedgerReason.duplicateMerge,
        operationId: operationId,
        at: timestamp,
      );
    }
    await txn.insert(DatabaseTables.libraryDeletionJournal, {
      'id': operationId,
      'operation': DeletionLedgerReason.duplicateMerge.name,
      'target_type': 'album',
      'target_id': merge.duplicateAlbumId,
      'summary': jsonEncode({
        'songs': merge.songIdRemap,
        'editions': {
          for (final p in merge.editionPairs)
            p.duplicateEditionId: p.keptEditionId,
        },
        'albums': {merge.duplicateAlbumId: merge.keptAlbumId},
        'movedPlays': merge.movedPlayCount,
      }),
      'committed_at': stamp,
    });

    // Cloud: a record the cloud has seen gets a delete; one it never saw
    // simply stops waiting to be sent.
    for (final (entity, ids) in [
      (CloudDataEntity.song, duplicateSongIds),
      (CloudDataEntity.albumEdition, duplicateEditionIds),
      (CloudDataEntity.album, [merge.duplicateAlbumId]),
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
  }
}

class DuplicateSongPair {
  const DuplicateSongPair({
    required this.keptSongId,
    required this.keptEditionId,
    required this.duplicateSongId,
  });

  final String keptSongId;

  /// The kept song's home edition; moved history is filed under it.
  final String keptEditionId;
  final String duplicateSongId;
}

class DuplicateEditionPair {
  const DuplicateEditionPair({
    required this.keptEditionId,
    required this.duplicateEditionId,
  });

  final String keptEditionId;
  final String duplicateEditionId;
}

/// One duplicate album merged into the album that stays.
class DuplicateMerge {
  const DuplicateMerge({
    required this.keptAlbumId,
    required this.duplicateAlbumId,
    required this.title,
    required this.songPairs,
    required this.editionPairs,
    required this.movedPlayCount,
    required this.movedLiveFileCount,
  });

  final String keptAlbumId;
  final String duplicateAlbumId;
  final String title;
  final List<DuplicateSongPair> songPairs;
  final List<DuplicateEditionPair> editionPairs;

  /// Qualified plays moved from the duplicate to the kept songs.
  final int movedPlayCount;

  /// Playable file links moved from the duplicate to the kept songs.
  final int movedLiveFileCount;

  /// Duplicate song id → the kept song id, for device-local references
  /// (the play queue, review lists) the database cannot update.
  Map<String, String> get songIdRemap => {
    for (final p in songPairs) p.duplicateSongId: p.keptSongId,
  };

  bool sameAs(DuplicateMerge other) =>
      keptAlbumId == other.keptAlbumId &&
      duplicateAlbumId == other.duplicateAlbumId &&
      _pairKey(songPairs) == _pairKey(other.songPairs);

  static String _pairKey(List<DuplicateSongPair> pairs) => jsonEncode([
    for (final p in [
      ...pairs,
    ]..sort((a, b) => a.duplicateSongId.compareTo(b.duplicateSongId)))
      [p.duplicateSongId, p.keptSongId],
  ]);
}

enum DuplicateReviewReason {
  /// The albums' songs or editions do not pair exactly.
  notVerified,

  /// The duplicate has stored weekly chart rows or Moments.
  hasChartHistory,
}

class DuplicateReview {
  const DuplicateReview({
    required this.albumIds,
    required this.title,
    required this.reason,
  });

  final List<String> albumIds;
  final String title;
  final DuplicateReviewReason reason;
}

class DuplicateReconciliationPlan {
  const DuplicateReconciliationPlan({
    required this.merges,
    required this.reviews,
  });

  final List<DuplicateMerge> merges;
  final List<DuplicateReview> reviews;
}

class DuplicateReconciliationReport {
  const DuplicateReconciliationReport({
    required this.merged,
    required this.stale,
    required this.reviews,
  });

  final List<DuplicateMerge> merged;
  final List<DuplicateMerge> stale;
  final List<DuplicateReview> reviews;
}

class _Song {
  _Song(Map<String, Object?> row)
    : id = row['id']! as String,
      editionId = row['album_edition_id']! as String,
      artistId = row['artist_id']! as String,
      canonicalTitle = row['canonical_title']! as String,
      versionLabel = TextNormalizer.canonicalize(
        row['version_label'] as String? ?? '',
      ),
      characteristics = row['version_characteristics'] as String? ?? '[]',
      featured = _canonicalSet(row['featured_artists'] as String? ?? '[]'),
      disc = row['disc_number']! as int,
      track = row['track_number']! as int,
      duration = row['duration_seconds']! as int;

  final String id;
  final String editionId;
  final String artistId;
  final String canonicalTitle;
  final String versionLabel;
  final String characteristics;
  final String featured;
  final int disc;
  final int track;
  final int duration;

  bool sameRecordingAs(_Song other) =>
      canonicalTitle == other.canonicalTitle &&
      versionLabel == other.versionLabel &&
      characteristics == other.characteristics &&
      artistId == other.artistId &&
      featured == other.featured &&
      disc == other.disc &&
      track > 0 &&
      track == other.track &&
      duration > 0 &&
      other.duration > 0 &&
      !RecordingEvidence.durationsDiffer(duration, other.duration);

  static String _canonicalSet(String json) {
    final names = <String>[];
    try {
      for (final name in jsonDecode(json) as List) {
        final canonical = TextNormalizer.canonicalize('$name');
        if (canonical.isNotEmpty) names.add(canonical);
      }
    } on FormatException {
      return json;
    }
    names.sort();
    return names.join('\u0000');
  }
}

class _Album {
  _Album({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.songs,
    required this.editions,
    required this.plays,
    required this.moments,
    required this.chartRows,
    required this.curated,
    required this.liveFiles,
  });

  final String id;
  final String title;
  final String createdAt;
  final List<_Song> songs;

  /// Edition id → (signature, release date, precision).
  final Map<String, (String, String?, String?)> editions;
  final int plays;
  final int moments;
  final int chartRows;
  final int curated;
  final int liveFiles;
}

class _DuplicatePlanner {
  _DuplicatePlanner(this.db);

  final DatabaseExecutor db;

  Future<DuplicateReconciliationPlan> plan() async {
    final groups = await db.rawQuery('''
      SELECT artist_id, canonical_title, GROUP_CONCAT(id, '|') AS ids
      FROM ${DatabaseTables.albums}
      GROUP BY artist_id, canonical_title
      HAVING COUNT(*) > 1
      ORDER BY artist_id, canonical_title
    ''');

    final merges = <DuplicateMerge>[];
    final reviews = <DuplicateReview>[];

    for (final group in groups) {
      final ids = (group['ids']! as String).split('|')..sort();
      final albums = [for (final id in ids) await _load(id)];
      albums.sort(_canonicalOrder);
      final kept = albums.first;

      for (final duplicate in albums.skip(1)) {
        final pairs = _pairSongs(kept, duplicate);
        final editionPairs = _pairEditions(kept, duplicate);
        if (pairs == null || editionPairs == null) {
          reviews.add(
            DuplicateReview(
              albumIds: [kept.id, duplicate.id],
              title: kept.title,
              reason: DuplicateReviewReason.notVerified,
            ),
          );
          continue;
        }
        if (duplicate.chartRows > 0 || duplicate.moments > 0) {
          reviews.add(
            DuplicateReview(
              albumIds: [kept.id, duplicate.id],
              title: kept.title,
              reason: DuplicateReviewReason.hasChartHistory,
            ),
          );
          continue;
        }
        merges.add(
          DuplicateMerge(
            keptAlbumId: kept.id,
            duplicateAlbumId: duplicate.id,
            title: kept.title,
            songPairs: pairs,
            editionPairs: editionPairs,
            movedPlayCount: duplicate.plays,
            movedLiveFileCount: duplicate.liveFiles,
          ),
        );
      }
    }

    return DuplicateReconciliationPlan(merges: merges, reviews: reviews);
  }

  /// Most listening, then Moments, then curated metadata, then the oldest.
  static int _canonicalOrder(_Album a, _Album b) {
    for (final c in [
      b.plays.compareTo(a.plays),
      b.moments.compareTo(a.moments),
      b.curated.compareTo(a.curated),
      a.createdAt.compareTo(b.createdAt),
      a.id.compareTo(b.id),
    ]) {
      if (c != 0) return c;
    }
    return 0;
  }

  /// One-to-one, unambiguous pairing of every song, or null.
  List<DuplicateSongPair>? _pairSongs(_Album kept, _Album duplicate) {
    if (kept.songs.length != duplicate.songs.length || kept.songs.isEmpty) {
      return null;
    }
    final unpaired = [...kept.songs];
    final pairs = <DuplicateSongPair>[];
    for (final song in duplicate.songs) {
      final candidates = unpaired.where(song.sameRecordingAs).toList();
      if (candidates.length != 1) return null;
      final match = candidates.single;
      if (kept.editions[match.editionId]?.$1 !=
          duplicate.editions[song.editionId]?.$1) {
        return null;
      }
      unpaired.remove(match);
      pairs.add(
        DuplicateSongPair(
          keptSongId: match.id,
          keptEditionId: match.editionId,
          duplicateSongId: song.id,
        ),
      );
    }
    return pairs;
  }

  /// Editions paired by type and title, with compatible release dates.
  List<DuplicateEditionPair>? _pairEditions(_Album kept, _Album duplicate) {
    if (kept.editions.length != duplicate.editions.length) return null;
    final bySignature = <String, String>{};
    for (final MapEntry(:key, :value) in kept.editions.entries) {
      if (bySignature.containsKey(value.$1)) return null;
      bySignature[value.$1] = key;
    }
    final pairs = <DuplicateEditionPair>[];
    for (final MapEntry(:key, :value) in duplicate.editions.entries) {
      final keptId = bySignature.remove(value.$1);
      if (keptId == null) return null;
      final keptEdition = kept.editions[keptId]!;
      if (!_compatibleDates(
        keptEdition.$2,
        keptEdition.$3,
        value.$2,
        value.$3,
      )) {
        return null;
      }
      pairs.add(
        DuplicateEditionPair(keptEditionId: keptId, duplicateEditionId: key),
      );
    }
    return pairs;
  }

  static bool _compatibleDates(
    String? a,
    String? aPrecision,
    String? b,
    String? bPrecision,
  ) {
    if (a == null || b == null) return true;
    final left = DateTime.tryParse(a);
    final right = DateTime.tryParse(b);
    if (left == null || right == null) return a == b;
    // Compare at the coarser precision. Stored year- and month-precision
    // dates may carry a time-zone offset, so the calendar fields are read
    // with a day of slack.
    const order = ['year', 'month', 'day'];
    final p = [
      order.indexOf(aPrecision ?? 'day'),
      order.indexOf(bPrecision ?? 'day'),
    ].reduce((x, y) => x < y ? x : y);
    final l = left.add(const Duration(hours: 12));
    final r = right.add(const Duration(hours: 12));
    if (l.year != r.year) return false;
    if (p >= 1 && l.month != r.month) return false;
    if (p >= 2 && l.day != r.day) return false;
    return true;
  }

  Future<_Album> _load(String albumId) async {
    final album = (await db.query(
      DatabaseTables.albums,
      where: 'id = ?',
      whereArgs: [albumId],
    )).single;
    final songs = [
      for (final row in await db.query(
        DatabaseTables.songs,
        where: 'album_id = ?',
        whereArgs: [albumId],
        orderBy: 'id',
      ))
        _Song(row),
    ];
    final songIds = [for (final s in songs) s.id];
    final editions = {
      for (final row in await db.query(
        DatabaseTables.albumEditions,
        where: 'album_id = ?',
        whereArgs: [albumId],
      ))
        row['id']! as String: (
          '${row['type']}\u0000'
              '${TextNormalizer.canonicalize(row['title']! as String)}',
          row['release_date'] as String?,
          row['release_date_precision'] as String?,
        ),
    };

    Future<int> count(String sql, List<Object?> args) async =>
        (await db.rawQuery(sql, args)).single['n']! as int;
    String marks(int n) => List.filled(n, '?').join(', ');
    final subjects = [albumId, ...songIds];

    return _Album(
      id: albumId,
      title: album['title']! as String,
      createdAt: album['created_at']! as String,
      songs: songs,
      editions: editions,
      plays: await count(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.qualifiedPlays} '
        'WHERE album_id = ?',
        [albumId],
      ),
      moments: await count(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.chartMomentEvents} '
        'WHERE entity_id IN (${marks(subjects.length)}) '
        'OR related_entity_id IN (${marks(subjects.length)})',
        [...subjects, ...subjects],
      ),
      chartRows: await count(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.chartEntries} '
        'WHERE entity_id IN (${marks(subjects.length)})',
        subjects,
      ),
      curated: await count(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.metadataFieldStates} '
        "WHERE authority IN ('manual', 'external', 'confirmed') AND ("
        "(entity_type = 'album' AND entity_id = ?) OR "
        "(entity_type = 'albumEdition' AND entity_id IN "
        '(SELECT id FROM ${DatabaseTables.albumEditions} WHERE album_id = ?)))',
        [albumId, albumId],
      ),
      liveFiles: await count(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.mediaFileBindings} mb '
        'JOIN ${DatabaseTables.songs} s ON s.id = mb.song_id '
        'WHERE s.album_id = ? AND mb.is_available = 1',
        [albumId],
      ),
    );
  }
}
