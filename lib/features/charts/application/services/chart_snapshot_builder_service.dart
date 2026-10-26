// ignore_for_file: prefer_initializing_formals

import '../../../analytics/domain/entities/playback_session.dart';
import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_ranked_entity.dart';
import '../../domain/models/chart_ranking_history.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/repositories/chart_repository.dart';
import '../../domain/services/chart_ranking_engine.dart';

class ChartSnapshotBuilderService {
  const ChartSnapshotBuilderService({
    required QualifiedPlayRepository qualifiedPlays,
    required LibraryQueryRepository library,
    required ChartRepository charts,
    PlaybackSessionRepository? playbackSessions,
    ChartRankingEngine rankingEngine = const ChartRankingEngine(),
  }) : _qualifiedPlays = qualifiedPlays,
       _library = library,
       _charts = charts,
       _playbackSessions = playbackSessions,
       _rankingEngine = rankingEngine;

  final QualifiedPlayRepository _qualifiedPlays;
  final LibraryQueryRepository _library;
  final ChartRepository _charts;
  final PlaybackSessionRepository? _playbackSessions;
  final ChartRankingEngine _rankingEngine;

  Future<ChartSnapshot> build({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    DateTime? finalizedAt,
    int revision = 1,
    ChartRankObservationCallback? onRankObservation,
    Set<String> excludedAlbumIds = const {},
  }) async {
    final startUtc = weekStartUtc.toUtc();
    final endUtc = weekEndUtc.toUtc();

    if (!endUtc.isAfter(startUtc)) {
      throw ArgumentError('Chart week end must be after chart week start.');
    }

    if (revision < 1) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Chart revision must be at least 1.',
      );
    }

    // Releases that never chart as releases (Singles) leave the release
    // chart entirely; their songs still chart.
    final plays = [
      for (final play in await _qualifiedPlays.getAll(
        qualifiedAtOrAfter: startUtc,
        qualifiedBefore: endUtc,
      ))
        if (chartType != ChartType.albums ||
            !excludedAlbumIds.contains(play.albumId))
          play,
    ];

    final history = await _charts.getHistory(chartType);

    final historyByEntityId = _buildHistoryContext(
      history: history,
      currentWeekStartUtc: startUtc,
    );

    final isHistoricalBuild = finalizedAt != null;

    Map<String, PlaybackSession> sessionsById = const {};

    if (isHistoricalBuild && plays.isNotEmpty) {
      final playbackSessions = _playbackSessions;

      if (playbackSessions == null) {
        throw StateError(
          'PlaybackSessionRepository is required for finalized chart builds.',
        );
      }

      final sessions = await playbackSessions.getByIds(
        plays.map((play) => play.playbackSessionId),
      );

      sessionsById = {for (final session in sessions) session.id: session};

      final missingSessionIds = plays
          .map((play) => play.playbackSessionId)
          .where((id) => !sessionsById.containsKey(id))
          .toSet();

      if (missingSessionIds.isNotEmpty) {
        throw StateError(
          'Cannot finalize chart with missing playback sessions: '
          '${missingSessionIds.join(', ')}',
        );
      }
    }

    switch (chartType) {
      case ChartType.songs:
        if (isHistoricalBuild) {
          return _buildHistoricalSongSnapshot(
            plays: plays,
            sessionsById: sessionsById,
            historyByEntityId: historyByEntityId,
            weekStartUtc: startUtc,
            weekEndUtc: endUtc,
            finalizedAt: finalizedAt,
            revision: revision,
          );
        }

        return _buildLiveSongSnapshot(
          plays: plays,
          historyByEntityId: historyByEntityId,
          weekStartUtc: startUtc,
          weekEndUtc: endUtc,
          revision: revision,
          onRankObservation: onRankObservation,
        );

      case ChartType.albums:
        if (isHistoricalBuild) {
          return _buildHistoricalAlbumSnapshot(
            plays: plays,
            sessionsById: sessionsById,
            historyByEntityId: historyByEntityId,
            weekStartUtc: startUtc,
            weekEndUtc: endUtc,
            finalizedAt: finalizedAt,
            revision: revision,
          );
        }

        return _buildLiveAlbumSnapshot(
          plays: plays,
          historyByEntityId: historyByEntityId,
          weekStartUtc: startUtc,
          weekEndUtc: endUtc,
          revision: revision,
          onRankObservation: onRankObservation,
        );
    }
  }

  Future<ChartSnapshot> _buildLiveSongSnapshot({
    required List<QualifiedPlay> plays,
    required Map<String, ChartRankingHistory> historyByEntityId,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required int revision,
    ChartRankObservationCallback? onRankObservation,
  }) async {
    final tracks = await _library.getTracks();

    final trackById = <String, LibraryTrack>{
      for (final track in tracks) track.songId: track,
    };

    final eligibleSongIds = tracks
        .where((track) => !track.isBlocked)
        .map((track) => track.songId)
        .toSet();

    final ranked = _rankingEngine.rank(
      events: _eventsFor(plays: plays, chartType: ChartType.songs),
      historyByEntityId: historyByEntityId,
      eligibleEntityIds: eligibleSongIds,
      onRankObservation: onRankObservation,
    );

    final entries = <ChartEntry>[];

    for (final result in ranked) {
      final track = trackById[result.entityId];

      if (track == null || track.isBlocked) {
        continue;
      }

      entries.add(
        _entryFromRanked(
          result: result,
          entity: ChartEntitySnapshot(
            entityId: track.songId,
            title: track.title,
            artistId: track.artistId,
            artistName: track.artistName,
            albumTitle: track.albumTitle,
          ),
          isFinalized: false,
        ),
      );
    }

    return _snapshot(
      chartType: ChartType.songs,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: null,
      revision: revision,
      entries: entries,
    );
  }

  Future<ChartSnapshot> _buildLiveAlbumSnapshot({
    required List<QualifiedPlay> plays,
    required Map<String, ChartRankingHistory> historyByEntityId,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required int revision,
    ChartRankObservationCallback? onRankObservation,
  }) async {
    final albums = await _library.getAlbums();

    final albumById = <String, LibraryAlbum>{
      for (final album in albums) album.albumId: album,
    };

    final ranked = _rankingEngine.rank(
      events: _eventsFor(plays: plays, chartType: ChartType.albums),
      historyByEntityId: historyByEntityId,
      eligibleEntityIds: albumById.keys.toSet(),
      onRankObservation: onRankObservation,
    );

    final entries = <ChartEntry>[];

    for (final result in ranked) {
      final album = albumById[result.entityId];

      if (album == null) {
        continue;
      }

      entries.add(
        _entryFromRanked(
          result: result,
          entity: ChartEntitySnapshot(
            entityId: album.albumId,
            title: album.title,
            artistId: album.artistId,
            artistName: album.artistName,
          ),
          isFinalized: false,
        ),
      );
    }

    return _snapshot(
      chartType: ChartType.albums,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: null,
      revision: revision,
      entries: entries,
    );
  }

  ChartSnapshot _buildHistoricalSongSnapshot({
    required List<QualifiedPlay> plays,
    required Map<String, PlaybackSession> sessionsById,
    required Map<String, ChartRankingHistory> historyByEntityId,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required DateTime finalizedAt,
    required int revision,
  }) {
    final identityBySongId = _historicalIdentityByEntity(
      plays: plays,
      sessionsById: sessionsById,
      chartType: ChartType.songs,
    );

    final ranked = _rankingEngine.rank(
      events: _eventsFor(plays: plays, chartType: ChartType.songs),
      historyByEntityId: historyByEntityId,
      includeObservedPeakInResult: false,
    );

    final entries = ranked
        .map(
          (result) => _entryFromRanked(
            result: result,
            entity: identityBySongId[result.entityId]!,
            isFinalized: true,
          ),
        )
        .toList(growable: false);

    return _snapshot(
      chartType: ChartType.songs,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: finalizedAt,
      revision: revision,
      entries: entries,
    );
  }

  ChartSnapshot _buildHistoricalAlbumSnapshot({
    required List<QualifiedPlay> plays,
    required Map<String, PlaybackSession> sessionsById,
    required Map<String, ChartRankingHistory> historyByEntityId,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required DateTime finalizedAt,
    required int revision,
  }) {
    final identityByAlbumId = _historicalIdentityByEntity(
      plays: plays,
      sessionsById: sessionsById,
      chartType: ChartType.albums,
    );

    final ranked = _rankingEngine.rank(
      events: _eventsFor(plays: plays, chartType: ChartType.albums),
      historyByEntityId: historyByEntityId,
      includeObservedPeakInResult: false,
    );

    final entries = ranked
        .map(
          (result) => _entryFromRanked(
            result: result,
            entity: identityByAlbumId[result.entityId]!,
            isFinalized: true,
          ),
        )
        .toList(growable: false);

    return _snapshot(
      chartType: ChartType.albums,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: finalizedAt,
      revision: revision,
      entries: entries,
    );
  }

  static List<ChartRankingEvent> _eventsFor({
    required List<QualifiedPlay> plays,
    required ChartType chartType,
  }) {
    return plays
        .map(
          (play) => ChartRankingEvent(
            entityId: switch (chartType) {
              ChartType.songs => play.songId,
              ChartType.albums => play.albumId,
            },
            qualifiedAt: play.qualifiedAt,
            sourceEventId: play.id,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, ChartEntitySnapshot> _historicalIdentityByEntity({
    required List<QualifiedPlay> plays,
    required Map<String, PlaybackSession> sessionsById,
    required ChartType chartType,
  }) {
    final ordered = [...plays]
      ..sort((a, b) {
        final timeCompare = a.qualifiedAt.toUtc().compareTo(
          b.qualifiedAt.toUtc(),
        );

        if (timeCompare != 0) {
          return timeCompare;
        }

        return a.id.compareTo(b.id);
      });

    final identities = <String, ChartEntitySnapshot>{};

    for (final play in ordered) {
      final session = sessionsById[play.playbackSessionId]!;

      switch (chartType) {
        case ChartType.songs:
          identities[play.songId] = ChartEntitySnapshot(
            entityId: play.songId,
            title: session.songTitle,
            artistId: session.artistId,
            artistName: session.artistName,
            albumTitle: session.albumTitle,
          );

        case ChartType.albums:
          identities[play.albumId] = ChartEntitySnapshot(
            entityId: play.albumId,
            title: session.albumTitle,
            artistId: session.artistId,
            artistName: session.artistName,
          );
      }
    }

    return identities;
  }

  static ChartEntry _entryFromRanked({
    required ChartRankedEntity result,
    required ChartEntitySnapshot entity,
    required bool isFinalized,
  }) {
    return ChartEntry(
      entity: entity,
      rank: result.rank,
      qualifiedStreamCount: result.qualifiedStreamCount,
      lastQualifiedAt: result.lastQualifiedAt,
      previousFinalRank: result.previousFinalRank,
      peakRank: result.peakRank,
      peakAchievedAt: result.peakAchievedAt,
      weeksOnChart: _resolvedWeeksOnChart(
        existingWeeks: result.weeksOnChart,
        rank: result.rank,
        isFinalized: isFinalized,
      ),
      movement: result.movement,
    );
  }

  static ChartSnapshot _snapshot({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required DateTime? finalizedAt,
    required int revision,
    required List<ChartEntry> entries,
  }) {
    return ChartSnapshot(
      id: _snapshotId(chartType: chartType, weekStartUtc: weekStartUtc),
      chartType: chartType,
      weekStartUtc: weekStartUtc,
      weekEndUtc: weekEndUtc,
      finalizedAt: finalizedAt?.toUtc(),
      revision: revision,
      entries: List<ChartEntry>.unmodifiable(entries),
    );
  }

  static Map<String, ChartRankingHistory> _buildHistoryContext({
    required List<ChartSnapshot> history,
    required DateTime currentWeekStartUtc,
  }) {
    final mutable = <String, _MutableHistory>{};

    for (final snapshot in history) {
      final snapshotStartUtc = snapshot.weekStartUtc.toUtc();

      if (!snapshotStartUtc.isBefore(currentWeekStartUtc.toUtc())) {
        continue;
      }

      final isPreviousWeek =
          snapshot.weekEndUtc.toUtc() == currentWeekStartUtc.toUtc();

      for (final entry in snapshot.entries) {
        final entityId = entry.entity.entityId;

        final state = mutable.putIfAbsent(
          entityId,
          () => _MutableHistory(entityId),
        );

        // Peak history spans the full persisted Top 200. This lets Moments
        // distinguish a genuine first Top-200 appearance from a return to
        // territory previously reached outside the official Top 100.
        if (state.peakRank == null || entry.peakRank < state.peakRank!) {
          state.peakRank = entry.peakRank;
          state.peakAchievedAt = entry.peakAchievedAt;
        } else if (entry.peakRank == state.peakRank &&
            state.peakAchievedAt != null &&
            entry.peakAchievedAt.isBefore(state.peakAchievedAt!)) {
          state.peakAchievedAt = entry.peakAchievedAt;
        }
        if (isPreviousWeek) {
          state.previousExtendedRank = entry.rank;
        }

        // Official chart career accounting remains Top 100 only.
        if (!entry.isOfficiallyCharting) {
          continue;
        }

        state.hasEverCharted = true;
        state.finalizedWeeksOnChart++;

        if (isPreviousWeek) {
          state.previousFinalRank = entry.rank;
        }
      }
    }

    return {
      for (final state in mutable.values)
        state.entityId: ChartRankingHistory(
          entityId: state.entityId,
          finalizedWeeksOnChart: state.finalizedWeeksOnChart,
          hasEverCharted: state.hasEverCharted,
          previousFinalRank: state.previousFinalRank,
          previousExtendedRank: state.previousExtendedRank,
          peakRank: state.peakRank,
          peakAchievedAt: state.peakAchievedAt,
        ),
    };
  }

  static int _resolvedWeeksOnChart({
    required int existingWeeks,
    required int rank,
    required bool isFinalized,
  }) {
    if (!isFinalized || rank > ChartRankingEngine.officialChartLimit) {
      return existingWeeks;
    }

    return existingWeeks + 1;
  }

  static String _snapshotId({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) {
    return 'chart_${chartType.name}_${weekStartUtc.toUtc().millisecondsSinceEpoch}';
  }
}

class _MutableHistory {
  _MutableHistory(this.entityId);

  final String entityId;

  int finalizedWeeksOnChart = 0;
  bool hasEverCharted = false;

  int? previousFinalRank;

  int? previousExtendedRank;

  int? peakRank;
  DateTime? peakAchievedAt;
}
