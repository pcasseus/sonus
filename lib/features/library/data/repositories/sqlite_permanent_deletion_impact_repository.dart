import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/deletion/permanent_deletion_impact.dart';

/// Computes [PermanentDeletionImpact] for a song, edition, album or artist.
///
/// Read-only: it only runs SELECT statements, so it is safe to run against
/// any database, including a read-only copy. PermanentDeletionService runs
/// it again inside its transaction and acts on the result. See
/// `_internal/APP_UPDATE_1_2_LIBRARY_DELETION_DESIGN.md`.
///
/// Pass a transaction when the result feeds an executor in the same
/// transaction, so the preview and the deletion see the same rows.
class SqlitePermanentDeletionImpactRepository {
  const SqlitePermanentDeletionImpactRepository(this._db);

  final DatabaseExecutor _db;

  static const int _chunk = 400;

  Future<PermanentDeletionImpact> plan(
    PermanentDeletionTarget target, {
    PermanentDeletionOptions options = const PermanentDeletionOptions(),
  }) async {
    final blockers = <PermanentDeletionBlocker>{};
    final songIds = <String>{};
    final albumIds = <String>{};
    final editionIds = <String>{};
    final artistIds = <String>{};
    final shared = <String>{};
    final keptLosingListing = <String>{};
    String? targetName;

    switch (target.kind) {
      case PermanentDeletionTargetKind.song:
        final rows = await _db.query(
          DatabaseTables.songs,
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [target.id],
        );
        if (rows.isEmpty) return _notFound(target);
        targetName = rows.single['title'] as String;
        songIds.add(target.id);

      case PermanentDeletionTargetKind.album:
        final rows = await _db.query(
          DatabaseTables.albums,
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [target.id],
        );
        if (rows.isEmpty) return _notFound(target);
        targetName = rows.single['title'] as String;
        await _collectAlbum(target.id, albumIds, editionIds, songIds);

      case PermanentDeletionTargetKind.edition:
        final rows = await _db.query(
          DatabaseTables.albumEditions,
          columns: ['title', 'album_id'],
          where: 'id = ?',
          whereArgs: [target.id],
        );
        if (rows.isEmpty) return _notFound(target);
        targetName = rows.single['title'] as String;
        final albumId = rows.single['album_id'] as String;
        final editionCount = Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseTables.albumEditions} '
            'WHERE album_id = ?',
            [albumId],
          ),
        )!;
        if (editionCount == 1) {
          // The only edition is the release itself.
          await _collectAlbum(albumId, albumIds, editionIds, songIds);
        } else {
          editionIds.add(target.id);
          final candidates = await _db.rawQuery(
            'SELECT id AS song_id FROM ${DatabaseTables.songs} '
            'WHERE album_edition_id = ? '
            'UNION '
            'SELECT song_id FROM ${DatabaseTables.albumEditionTracks} '
            'WHERE album_edition_id = ?',
            [target.id, target.id],
          );
          for (final row in candidates) {
            final songId = row['song_id'] as String;
            final elsewhere = Sqflite.firstIntValue(
              await _db.rawQuery(
                'SELECT COUNT(*) FROM ${DatabaseTables.albumEditionTracks} '
                'WHERE song_id = ? AND album_edition_id <> ?',
                [songId, target.id],
              ),
            )!;
            (elsewhere > 0 ? keptLosingListing : songIds).add(songId);
          }
        }

      case PermanentDeletionTargetKind.artist:
        final rows = await _db.query(
          DatabaseTables.artists,
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [target.id],
        );
        if (rows.isEmpty) return _notFound(target);
        targetName = rows.single['name'] as String;
        artistIds.add(target.id);
        final ownedAlbums = await _db.query(
          DatabaseTables.albums,
          columns: ['id'],
          where: 'artist_id = ?',
          whereArgs: [target.id],
        );
        for (final row in ownedAlbums) {
          await _collectAlbum(row['id'] as String, albumIds, editionIds, {});
        }
        final onOwnReleases = await _selectIn(
          'SELECT id, artist_id FROM ${DatabaseTables.songs} WHERE album_id',
          albumIds,
        );
        for (final row in onOwnReleases) {
          final id = row['id'] as String;
          if (row['artist_id'] == target.id) {
            songIds.add(id);
          } else {
            shared.add(id);
          }
        }
        final elsewhere = await _db.query(
          DatabaseTables.songs,
          columns: ['id', 'album_id'],
          where: 'artist_id = ?',
          whereArgs: [target.id],
        );
        for (final row in elsewhere) {
          if (!albumIds.contains(row['album_id'])) {
            shared.add(row['id'] as String);
          }
        }
        if (shared.isNotEmpty) {
          if (options.includeSharedRecordings) {
            songIds.addAll(shared);
          } else {
            blockers.add(PermanentDeletionBlocker.sharedRecordingsNotConfirmed);
          }
        }
    }

    // Credits on songs that stay.
    final collaborationKept = <String>{};
    var creditLinksRemoved = 0;
    if (artistIds.isNotEmpty) {
      final credits = await _db.query(
        DatabaseTables.songArtistCredits,
        columns: ['song_id'],
        where: 'artist_id = ?',
        whereArgs: [target.id],
      );
      for (final row in credits) {
        final songId = row['song_id'] as String;
        if (!songIds.contains(songId) && !shared.contains(songId)) {
          collaborationKept.add(songId);
          creditLinksRemoved++;
        }
      }
    }

    // Listening history: sessions of deleted songs, plus sessions that still
    // name a deleted release or artist but whose song no longer exists.
    final sessionIds = <String>{
      for (final row in await _selectIn(
        'SELECT id FROM ${DatabaseTables.playbackSessions} WHERE song_id',
        songIds,
      ))
        row['id'] as String,
    };
    final orphanScopes = <String, Set<String>>{
      'album_id': albumIds,
      'artist_id': artistIds,
    };
    for (final MapEntry(key: column, value: ids) in orphanScopes.entries) {
      for (final row in await _selectIn(
        'SELECT id FROM ${DatabaseTables.playbackSessions} '
        'WHERE song_id NOT IN (SELECT id FROM ${DatabaseTables.songs}) '
        'AND $column',
        ids,
      )) {
        sessionIds.add(row['id'] as String);
      }
    }
    final playRows = <Map<String, Object?>>[
      ...await _selectIn(
        'SELECT id, qualified_at FROM ${DatabaseTables.qualifiedPlays} '
        'WHERE playback_session_id',
        sessionIds,
      ),
      ...await _selectIn(
        'SELECT id, qualified_at FROM ${DatabaseTables.qualifiedPlays} '
        'WHERE song_id',
        songIds,
      ),
    ];
    final playIds = {for (final r in playRows) r['id'] as String};
    final playTimes = {for (final r in playRows) r['qualified_at'] as String};

    var segments = 0;
    var listenedMs = 0;
    for (final row in await _selectIn(
      'SELECT listened_duration_ms, '
      '(SELECT COUNT(*) FROM ${DatabaseTables.playbackListeningSegments} g '
      'WHERE g.playback_session_id = s.id) AS segments '
      'FROM ${DatabaseTables.playbackSessions} s WHERE id',
      sessionIds,
    )) {
      listenedMs += row['listened_duration_ms'] as int;
      segments += row['segments'] as int;
    }

    var repointed = 0;
    if (target.kind == PermanentDeletionTargetKind.edition &&
        editionIds.contains(target.id)) {
      for (final table in [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
      ]) {
        for (final row in await _selectIn(
          'SELECT COUNT(*) AS n FROM $table WHERE album_edition_id = ? '
          'AND song_id',
          keptLosingListing,
          leadingArgs: [target.id],
        )) {
          repointed += row['n'] as int;
        }
      }
    }

    // Stored weekly charts.
    final chartEntryIds = <String>{};
    final affectedWeeks = <String>{};
    for (final (chartType, ids) in [('songs', songIds), ('albums', albumIds)]) {
      for (final row in await _selectIn(
        'SELECT e.id, s.chart_type, s.week_start_utc '
        'FROM ${DatabaseTables.chartEntries} e '
        'JOIN ${DatabaseTables.chartSnapshots} s ON s.id = e.chart_snapshot_id '
        'WHERE s.chart_type = ? AND e.entity_id',
        ids,
        leadingArgs: [chartType],
      )) {
        chartEntryIds.add(row['id'] as String);
        affectedWeeks.add('${row['chart_type']}:${row['week_start_utc']}');
      }
    }
    // A deleted play also lowers its release's total on the album chart,
    // even when the release stays.
    if (playTimes.isNotEmpty) {
      final snapshots = await _db.query(
        DatabaseTables.chartSnapshots,
        columns: ['chart_type', 'week_start_utc', 'week_end_utc'],
        where: "chart_type = 'albums'",
      );
      for (final s in snapshots) {
        final start = DateTime.parse(s['week_start_utc'] as String);
        final end = DateTime.parse(s['week_end_utc'] as String);
        if (playTimes.any((t) {
          final at = DateTime.parse(t);
          return !at.isBefore(start) && at.isBefore(end);
        })) {
          affectedWeeks.add('albums:${s['week_start_utc']}');
        }
      }
    }

    // Moments.
    final subjects = {...songIds, ...albumIds, ...artistIds};
    final about = <String>{
      for (final row in await _selectIn(
        'SELECT id FROM ${DatabaseTables.chartMomentEvents} WHERE entity_id',
        subjects,
      ))
        row['id'] as String,
    };
    final mentioning = <String>{};
    final mentionQueries = <(String, Set<String>)>[
      ('related_entity_id', subjects),
      ('entity_artist_id', artistIds),
      ('related_entity_artist_id', artistIds),
      ('source_id', playIds),
    ];
    for (final (column, ids) in mentionQueries) {
      for (final row in await _selectIn(
        'SELECT id FROM ${DatabaseTables.chartMomentEvents} WHERE $column',
        ids,
      )) {
        mentioning.add(row['id'] as String);
      }
    }
    if (playIds.isNotEmpty) {
      // Exits are keyed `exit:<causing play id>:<exited entity id>`.
      final exits = await _db.query(
        DatabaseTables.chartMomentEvents,
        columns: ['id', 'source_id'],
        where: "source_id LIKE 'exit:%'",
      );
      for (final row in exits) {
        final parts = (row['source_id'] as String).split(':');
        if (parts.length >= 3 && playIds.contains(parts[1])) {
          mentioning.add(row['id'] as String);
        }
      }
    }
    mentioning.removeAll(about);

    // Playlists.
    final playlistCounts = <String, (String, int)>{};
    for (final row in await _selectIn(
      'SELECT p.id, p.name FROM ${DatabaseTables.playlistItems} i '
      'JOIN ${DatabaseTables.playlists} p ON p.id = i.playlist_id '
      'WHERE i.song_id',
      songIds,
    )) {
      final id = row['id'] as String;
      final current = playlistCounts[id];
      playlistCounts[id] = (row['name'] as String, (current?.$2 ?? 0) + 1);
    }
    final playlists = [
      for (final MapEntry(:key, :value) in playlistCounts.entries)
        PlaylistDeletionImpact(
          playlistId: key,
          playlistName: value.$1,
          itemsRemoved: value.$2,
        ),
    ]..sort((a, b) => a.playlistName.compareTo(b.playlistName));

    final bindings = await _countIn(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.mediaFileBindings} '
      'WHERE song_id',
      songIds,
    );
    final lyrics = await _countIn(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.trackLyrics} WHERE song_id',
      songIds,
    );

    var metadataStates = 0;
    var pendingWrites = 0;
    for (final (type, ids) in [
      ('song', songIds),
      ('album', albumIds),
      ('albumEdition', editionIds),
      ('artist', artistIds),
    ]) {
      metadataStates += await _countIn(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.metadataFieldStates} '
        'WHERE entity_type = ? AND entity_id',
        ids,
        leadingArgs: [type],
      );
      pendingWrites += await _countIn(
        'SELECT COUNT(*) AS n FROM ${DatabaseTables.syncOutbox} '
        'WHERE entity_type = ? AND entity_id',
        ids,
        leadingArgs: [type],
      );
    }
    if (pendingWrites > 0) {
      blockers.add(PermanentDeletionBlocker.pendingCloudWrite);
    }

    var crops = await _countIn(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.artworkCrops} '
      "WHERE target_type = 'albumEdition' AND target_id",
      editionIds,
    );
    crops += await _countIn(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.artworkCrops} '
      "WHERE target_type IN ('artistBanner', 'artistPortrait') AND target_id",
      artistIds,
    );

    // Artwork only the deleted records use (exact: every other reference
    // is checked).
    final artworkCandidates = <String>{};
    void addArtwork(Object? id) {
      if (id is String && id.isNotEmpty) artworkCandidates.add(id);
    }

    for (final row in await _selectIn(
      'SELECT artwork_id FROM ${DatabaseTables.songs} WHERE id',
      songIds,
    )) {
      addArtwork(row['artwork_id']);
    }
    for (final row in await _selectIn(
      'SELECT artwork_id FROM ${DatabaseTables.albumEditions} WHERE id',
      editionIds,
    )) {
      addArtwork(row['artwork_id']);
    }
    for (final row in await _selectIn(
      'SELECT header_artwork_id, top_artists_artwork_id '
      'FROM ${DatabaseTables.artists} WHERE id',
      artistIds,
    )) {
      addArtwork(row['header_artwork_id']);
      addArtwork(row['top_artists_artwork_id']);
    }
    final deletedCropTargets = {...editionIds, ...artistIds};
    for (final row in await _selectIn(
      'SELECT source_artwork_id, output_artwork_id '
      'FROM ${DatabaseTables.artworkCrops} WHERE target_id',
      deletedCropTargets,
    )) {
      addArtwork(row['source_artwork_id']);
      addArtwork(row['output_artwork_id']);
    }
    final artworkAssetIds = <String>{};
    for (final artworkId in artworkCandidates) {
      final stillUsed =
          (await _db.rawQuery(
            'SELECT id FROM ${DatabaseTables.songs} WHERE artwork_id = ?',
            [artworkId],
          )).any((r) => !songIds.contains(r['id'])) ||
          (await _db.rawQuery(
            'SELECT id FROM ${DatabaseTables.albumEditions} '
            'WHERE artwork_id = ?',
            [artworkId],
          )).any((r) => !editionIds.contains(r['id'])) ||
          (await _db.rawQuery(
            'SELECT id FROM ${DatabaseTables.artists} '
            'WHERE header_artwork_id = ? OR top_artists_artwork_id = ?',
            [artworkId, artworkId],
          )).any((r) => !artistIds.contains(r['id'])) ||
          (await _db.rawQuery(
            'SELECT target_id FROM ${DatabaseTables.artworkCrops} '
            'WHERE source_artwork_id = ? OR output_artwork_id = ?',
            [artworkId, artworkId],
          )).any((r) => !deletedCropTargets.contains(r['target_id']));
      if (!stillUsed) artworkAssetIds.add(artworkId);
    }

    final targetArtworkId = switch (target.kind) {
      PermanentDeletionTargetKind.song => await _firstString(
        'SELECT COALESCE(s.artwork_id, e.artwork_id) AS a '
        'FROM ${DatabaseTables.songs} s '
        'JOIN ${DatabaseTables.albumEditions} e ON e.id = s.album_edition_id '
        'WHERE s.id = ?',
        target.id,
      ),
      PermanentDeletionTargetKind.edition => await _firstString(
        'SELECT artwork_id AS a FROM ${DatabaseTables.albumEditions} '
        'WHERE id = ?',
        target.id,
      ),
      PermanentDeletionTargetKind.album => await _firstString(
        'SELECT artwork_id AS a FROM ${DatabaseTables.albumEditions} '
        'WHERE album_id = ? ORDER BY is_primary DESC, created_at LIMIT 1',
        target.id,
      ),
      PermanentDeletionTargetKind.artist => await _firstString(
        'SELECT header_artwork_id AS a FROM ${DatabaseTables.artists} '
        'WHERE id = ?',
        target.id,
      ),
    };

    final losingGrouping = <String>{
      for (final row in await _selectIn(
        'SELECT artist_id FROM ${DatabaseTables.artistProjectAssignments} '
        'WHERE album_id',
        albumIds,
      ))
        if (!artistIds.contains(row['artist_id'])) row['artist_id'] as String,
    };

    return PermanentDeletionImpact(
      target: target,
      targetName: targetName,
      blockers: blockers,
      songIds: songIds,
      albumIds: albumIds,
      editionIds: editionIds,
      artistIds: artistIds,
      sharedRecordingIds: shared,
      songsKeptLosingListing: keptLosingListing,
      collaborationSongIdsKept: collaborationKept,
      creditLinksRemoved: creditLinksRemoved,
      playbackSessionIds: sessionIds,
      qualifiedPlayIds: playIds,
      listeningSegmentCount: segments,
      listenedMs: listenedMs,
      historyRowsRepointed: repointed,
      chartEntryIds: chartEntryIds,
      affectedChartWeeks: affectedWeeks,
      momentIdsAboutTarget: about,
      momentIdsMentioningTarget: mentioning,
      playlists: playlists,
      mediaFileBindingCount: bindings,
      lyricsCount: lyrics,
      metadataFieldStateCount: metadataStates,
      artworkCropCount: crops,
      otherArtistsLosingProjectGrouping: losingGrouping,
      pendingCloudWriteCount: pendingWrites,
      artworkAssetIds: artworkAssetIds,
      targetArtworkId: targetArtworkId,
    );
  }

  Future<String?> _firstString(String sql, String arg) async {
    final rows = await _db.rawQuery(sql, [arg]);
    return rows.isEmpty ? null : rows.first['a'] as String?;
  }

  Future<void> _collectAlbum(
    String albumId,
    Set<String> albumIds,
    Set<String> editionIds,
    Set<String> songIds,
  ) async {
    albumIds.add(albumId);
    for (final row in await _db.query(
      DatabaseTables.albumEditions,
      columns: ['id'],
      where: 'album_id = ?',
      whereArgs: [albumId],
    )) {
      editionIds.add(row['id'] as String);
    }
    for (final row in await _db.query(
      DatabaseTables.songs,
      columns: ['id'],
      where: 'album_id = ?',
      whereArgs: [albumId],
    )) {
      songIds.add(row['id'] as String);
    }
  }

  /// Runs `<prefix> IN (?, …)` over [ids] in chunks. [prefix] ends with the
  /// column name.
  Future<List<Map<String, Object?>>> _selectIn(
    String prefix,
    Set<String> ids, {
    List<Object?> leadingArgs = const [],
  }) async {
    if (ids.isEmpty) return const [];
    final list = ids.toList();
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < list.length; i += _chunk) {
      final part = list.sublist(i, (i + _chunk).clamp(0, list.length));
      final marks = List.filled(part.length, '?').join(', ');
      out.addAll(
        await _db.rawQuery('$prefix IN ($marks)', [...leadingArgs, ...part]),
      );
    }
    return out;
  }

  Future<int> _countIn(
    String prefix,
    Set<String> ids, {
    List<Object?> leadingArgs = const [],
  }) async {
    var total = 0;
    for (final row in await _selectIn(prefix, ids, leadingArgs: leadingArgs)) {
      total += row['n'] as int;
    }
    return total;
  }

  PermanentDeletionImpact _notFound(PermanentDeletionTarget target) =>
      PermanentDeletionImpact(
        target: target,
        targetName: null,
        blockers: const {PermanentDeletionBlocker.notFound},
        songIds: const {},
        albumIds: const {},
        editionIds: const {},
        artistIds: const {},
        sharedRecordingIds: const {},
        songsKeptLosingListing: const {},
        collaborationSongIdsKept: const {},
        creditLinksRemoved: 0,
        playbackSessionIds: const {},
        qualifiedPlayIds: const {},
        listeningSegmentCount: 0,
        listenedMs: 0,
        historyRowsRepointed: 0,
        chartEntryIds: const {},
        affectedChartWeeks: const {},
        momentIdsAboutTarget: const {},
        momentIdsMentioningTarget: const {},
        playlists: const [],
        mediaFileBindingCount: 0,
        lyricsCount: 0,
        metadataFieldStateCount: 0,
        artworkCropCount: 0,
        otherArtistsLosingProjectGrouping: const {},
        pendingCloudWriteCount: 0,
      );
}
