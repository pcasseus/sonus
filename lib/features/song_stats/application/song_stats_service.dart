// ignore_for_file: prefer_initializing_formals

import '../../analytics/application/services/pulse/pulse_listening_records.dart';
import '../../charts/application/services/this_week_chart_service.dart';
import '../../charts/domain/models/chart_type.dart';
import '../../charts/domain/repositories/chart_entity_history_reader.dart';
import '../../charts/domain/services/chart_week_resolver.dart';
import '../../library/application/repositories/library_query_repository.dart';
import 'song_listening_records.dart';
import 'song_stats_models.dart';

/// What the Song Stats page needs.
abstract interface class SongStatsLoader {
  Future<SongStats> load(String songId);
}

/// Assembles one song's stats from what Sonus recorded. Read-only: it never
/// writes, rebuilds or finalizes anything.
///
/// - Chart history: stored finalized weeks exactly as they were finalized,
///   plus the provisional week in progress, kept apart.
/// - Listening: Sonus Pulse definitions (segments for minutes, qualified
///   plays for streams, audible sessions for all plays).
class SongStatsService implements SongStatsLoader {
  SongStatsService({
    required ChartEntityHistoryReader charts,
    required Future<SongListeningRecords> Function() records,
    required LibraryQueryRepository library,
    Future<ProvisionalWeekChart?> Function()? liveSongs,
    DateTime Function()? nowLocal,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    this.trendWeeks = 8,
  }) : _charts = charts,
       _records = records,
       _library = library,
       _liveSongs = liveSongs,
       _nowLocal = nowLocal ?? DateTime.now,
       _weekResolver = weekResolver;

  final ChartEntityHistoryReader _charts;
  final Future<SongListeningRecords> Function() _records;
  final LibraryQueryRepository _library;
  final Future<ProvisionalWeekChart?> Function()? _liveSongs;
  final DateTime Function() _nowLocal;
  final ChartWeekResolver _weekResolver;

  /// How many chart weeks the listening trend covers (current included).
  final int trendWeeks;

  @override
  Future<SongStats> load(String songId) async {
    final recordsFuture = _records();
    final trackFuture = _library.getTrackById(songId);
    final weeksFuture = _charts.finalizedWeeksFor(ChartType.songs, songId);
    final liveFuture = _readLive();

    final records = await recordsFuture;
    final segmentsFuture = records.segmentsForSong(songId);
    final streamsFuture = records.qualifiedPlaysForSong(songId);
    final playsFuture = records.audibleSessionsForSong(songId);
    final playedAsFuture = records.lastPlayedIdentity(songId);
    final historyFuture = records.firstSessionStartedAt();

    final track = await trackFuture;
    final stored = await weeksFuture;
    final live = await liveFuture;

    final liveEntry = live?.snapshot.entries
        .where((entry) => entry.entity.entityId == songId)
        .firstOrNull;
    final chart = SongChartHistory(
      weeks: chartWeeks(stored),
      live: liveEntry == null
          ? null
          : SongLiveChart(
              entry: liveEntry,
              weekStartUtc: live!.snapshot.weekStartUtc,
              weekEndUtc: live.snapshot.weekEndUtc,
              bestSoFarRank: live.bestSoFarRank(songId),
            ),
    );

    final listening = _listening(
      segments: await segmentsFuture,
      streams: await streamsFuture,
      plays: await playsFuture,
      historyStartedAt: await historyFuture,
    );

    final playedAs = await playedAsFuture;
    final chartName = (liveEntry ?? stored.lastOrNull?.entry)?.entity;
    final identity = SongStatsIdentity(
      songId: songId,
      title: _first([
        track?.displayTitle,
        playedAs?.title,
        chartName?.title,
      ], 'Unknown track'),
      artistLine: _first([
        track?.creditLine,
        playedAs?.artistName,
        chartName?.artistName,
      ], ''),
      albumTitle: _firstOrNull([
        track?.albumDisplayTitle,
        playedAs?.albumTitle,
        chartName?.albumTitle,
      ]),
      artworkPath: track?.artworkPath,
      status: SongStatsStatus.of(track),
      track: track,
    );

    return SongStats(identity: identity, chart: chart, listening: listening);
  }

  Future<ProvisionalWeekChart?> _readLive() async {
    final read = _liveSongs;
    if (read == null) return null;
    try {
      return await read();
    } on Object {
      // The live week is optional: finalized history still shows.
      return null;
    }
  }

  /// Finalized weeks with their relation to the previous recorded week.
  static List<SongChartWeek> chartWeeks(List<ChartEntityWeek> stored) {
    final sorted = [...stored]
      ..sort((a, b) => a.weekStartUtc.compareTo(b.weekStartUtc));
    final result = <SongChartWeek>[];
    int? best;
    var hot100Before = false;
    for (var i = 0; i < sorted.length; i++) {
      final week = sorted[i];
      final rank = week.entry.rank;
      final previous = i == 0 ? null : sorted[i - 1];
      final gap = previous == null
          ? null
          : weekIndex(week.weekStartUtc) - weekIndex(previous.weekStartUtc);
      final previousRank = gap == 1 ? previous!.entry.rank : null;

      final SongChartWeekEvent event;
      if (previous == null) {
        event = SongChartWeekEvent.debut;
      } else if (previousRank == null) {
        event = SongChartWeekEvent.reentry;
      } else if ((previousRank <= 100) == (rank <= 100)) {
        event = rank < previousRank
            ? SongChartWeekEvent.up
            : rank > previousRank
            ? SongChartWeekEvent.down
            : SongChartWeekEvent.same;
      } else {
        event = rank <= 100
            ? SongChartWeekEvent.promoted
            : SongChartWeekEvent.demoted;
      }

      result.add(
        SongChartWeek(
          weekStartUtc: week.weekStartUtc,
          weekEndUtc: week.weekEndUtc,
          rank: rank,
          previousRank: previousRank,
          event: event,
          newPeak: best != null && rank < best,
          hot100Debut: rank <= 100 && !hot100Before,
          weeksOff: event == SongChartWeekEvent.reentry && gap != null
              ? gap - 1
              : 0,
        ),
      );
      if (best == null || rank < best) best = rank;
      if (rank <= 100) hot100Before = true;
    }
    return result;
  }

  /// A chart week's number, counted in local Sunday-start weeks.
  static int weekIndex(DateTime weekStartUtc) {
    final local = weekStartUtc.toLocal();
    final day = DateTime.utc(local.year, local.month, local.day);
    return (day.difference(DateTime.utc(2000, 1, 2)).inHours / (24 * 7))
        .round();
  }

  SongListeningStats _listening({
    required List<PulseSegmentRecord> segments,
    required List<PulsePlayRecord> streams,
    required List<PulsePlayRecord> plays,
    required DateTime? historyStartedAt,
  }) {
    var listened = Duration.zero;
    for (final segment in segments) {
      listened += _length(segment, null, null);
    }

    DateTime? first;
    DateTime? last;
    for (final play in plays) {
      final at = play.at.toUtc();
      if (first == null || at.isBefore(first)) first = at;
      if (last == null || at.isAfter(last)) last = at;
    }

    // Recent chart weeks, never before recorded history began.
    final current = _weekResolver.resolve(_nowLocal());
    final currentStart = current.startUtc.toLocal();
    final historyWeek = historyStartedAt == null
        ? null
        : _weekResolver.resolve(historyStartedAt.toLocal());
    final weeks = <SongListeningWeek>[];
    for (var back = trendWeeks - 1; back >= 0; back--) {
      final weekStart = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day - 7 * back,
      );
      final weekEnd = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + 7,
      );
      final startUtc = weekStart.toUtc();
      final endUtc = weekEnd.toUtc();
      if (historyWeek == null || !endUtc.isAfter(historyWeek.startUtc)) {
        continue;
      }
      var weekListened = Duration.zero;
      for (final segment in segments) {
        weekListened += _length(segment, startUtc, endUtc);
      }
      bool inWeek(PulsePlayRecord p) =>
          !p.at.toUtc().isBefore(startUtc) && p.at.toUtc().isBefore(endUtc);
      weeks.add(
        SongListeningWeek(
          weekStartLocal: weekStart,
          listened: weekListened,
          streams: streams.where(inWeek).length,
          allPlays: plays.where(inWeek).length,
          inProgress: back == 0,
        ),
      );
    }

    return SongListeningStats(
      streams: streams.length,
      listened: listened,
      allPlays: plays.length,
      firstPlayedAt: first,
      lastPlayedAt: last,
      weeks: weeks,
      historyStartedAt: historyStartedAt,
    );
  }

  /// A segment's audible time inside [start]..[end] (open bounds when
  /// null), by the Pulse rule: from its start to its truthful end.
  static Duration _length(
    PulseSegmentRecord segment,
    DateTime? start,
    DateTime? end,
  ) {
    var from = segment.startedAt.toUtc();
    var to = segment.truthfulEnd;
    if (start != null && from.isBefore(start)) from = start;
    if (end != null && to.isAfter(end)) to = end;
    return to.isAfter(from) ? to.difference(from) : Duration.zero;
  }

  static String _first(List<String?> values, String fallback) =>
      _firstOrNull(values) ?? fallback;

  static String? _firstOrNull(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }
}
