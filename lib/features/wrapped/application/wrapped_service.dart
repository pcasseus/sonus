// ignore_for_file: prefer_initializing_formals

import '../../analytics/application/models/pulse/pulse_period.dart';
import '../../analytics/application/models/pulse/pulse_period_data.dart';
import '../../analytics/application/services/pulse/pulse_entity_directory.dart';
import '../../analytics/application/services/pulse/pulse_insights_service.dart';
import '../../library/domain/services/genre_catalog.dart';
import 'wrapped_history_reader.dart';
import 'wrapped_summary.dart';

/// The periods Sonus Wrapped can show: every month and year from the first
/// recorded session to today, newest first.
class WrappedArchive {
  const WrappedArchive({
    required this.historyStartLocal,
    required this.years,
    required this.months,
  });

  static const empty = WrappedArchive(
    historyStartLocal: null,
    years: [],
    months: [],
  );

  final DateTime? historyStartLocal;
  final List<PulsePeriod> years;
  final List<PulsePeriod> months;

  bool get isEmpty => years.isEmpty;
}

/// What Sonus Wrapped needs from the data layer.
abstract interface class WrappedLoader {
  Future<WrappedArchive> archive();

  Future<WrappedSummary> load(PulsePeriod period);
}

/// Builds Sonus Wrapped from Sonus Pulse's period data (the same streams,
/// minutes, rankings and comparisons, so the numbers always agree) and a
/// few read-only history queries: genres, lifetime milestones and stored
/// chart #1s. Nothing is written, cached on disk or estimated.
class WrappedService implements WrappedLoader {
  WrappedService({
    required PulsePeriodLoader pulse,
    required PulseDirectoryLoader directory,
    required WrappedHistoryReader history,
    DateTime Function()? nowLocal,
  }) : _pulse = pulse,
       _directory = directory,
       _history = history,
       _nowLocal = nowLocal ?? DateTime.now;

  final PulsePeriodLoader _pulse;
  final PulseDirectoryLoader _directory;
  final WrappedHistoryReader _history;
  final DateTime Function() _nowLocal;

  /// Top lists hold the ten highest.
  static const int topCount = 10;

  /// Lifetime stream counts worth telling when they are reached.
  static const List<int> lifetimeMilestones = [
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
    25000,
    50000,
    100000,
  ];

  @override
  Future<WrappedArchive> archive() async {
    final first = await _pulse.firstHistoryAt();
    if (first == null) return WrappedArchive.empty;
    final start = first.toLocal();
    final now = _nowLocal();
    return WrappedArchive(
      historyStartLocal: start,
      years: [
        for (var year = now.year; year >= start.year; year--)
          PulsePeriod.year(year),
      ],
      months: [
        for (
          var month = PulsePeriod.month(now.year, now.month);
          !month.endLocal.isBefore(DateTime(start.year, start.month, 2));
          month = month.previous
        )
          month,
      ],
    );
  }

  @override
  Future<WrappedSummary> load(PulsePeriod period) async {
    final data = await _pulse.load(period);
    final state = stateOf(period, data.firstHistoryAt, _nowLocal());
    final directory = await _directory.load(data);
    final previous = period.previous;
    final previousData = data.previous.isAvailable
        ? await _pulse.load(previous)
        : null;
    final (genres, withoutGenre) = await _genres(period, data.totals.streams);
    final (numberOnes, chartWeeks) = await _numberOnes(period);
    return WrappedSummary(
      period: period,
      state: state,
      historyStartLocal: _historyStartInside(period, data.firstHistoryAt),
      totals: totalsOf(data),
      topSongs: _top(data, directory, PulseEntityKind.track),
      topArtists: _top(data, directory, PulseEntityKind.artist),
      topAlbums: _top(data, directory, PulseEntityKind.release),
      genres: genres,
      streamsWithoutGenre: withoutGenre,
      days: [
        for (final day in data.days)
          WrappedActivityPoint(
            startLocal: day.localDate,
            endLocal: DateTime(
              day.localDate.year,
              day.localDate.month,
              day.localDate.day + 1,
            ),
            streams: day.metrics.streams,
            listened: day.metrics.listened,
            recorded: day.state == PulseDayState.recorded,
          ),
      ],
      weeks: _weeks(data),
      months: period.kind == PulsePeriodKind.year
          ? await _months(period, directory)
          : const [],
      comparison: WrappedComparison(
        previous: previous,
        state: previousData == null
            ? WrappedComparisonState.notEnoughHistory
            : WrappedComparisonState.available,
        totals: previousData == null ? null : totalsOf(previousData),
      ),
      milestones: await _milestones(period, data),
      chartNumberOnes: numberOnes,
      chartWeeks: chartWeeks,
    );
  }

  /// Where [period] stands against history beginning at [firstHistoryAt]
  /// and today ([nowLocal]).
  static WrappedPeriodState stateOf(
    PulsePeriod period,
    DateTime? firstHistoryAt,
    DateTime nowLocal,
  ) {
    if (nowLocal.isBefore(period.startLocal)) return WrappedPeriodState.future;
    if (firstHistoryAt == null ||
        !firstHistoryAt.toLocal().isBefore(period.endLocal)) {
      return WrappedPeriodState.beforeHistory;
    }
    if (nowLocal.isBefore(period.endLocal)) {
      return WrappedPeriodState.inProgress;
    }
    return WrappedPeriodState.complete;
  }

  static DateTime? _historyStartInside(PulsePeriod period, DateTime? first) {
    if (first == null) return null;
    final local = first.toLocal();
    return local.isAfter(period.startLocal) && local.isBefore(period.endLocal)
        ? local
        : null;
  }

  /// [data]'s headline numbers. Albums are Albums & EPs, as in the top
  /// albums (Singles are left out of release rankings).
  static WrappedTotals totalsOf(PulsePeriodData data) {
    final overview = data.overview;
    return WrappedTotals(
      streams: overview.streams,
      listened: overview.listened,
      allPlays: overview.allPlays,
      activeDays: overview.activeDays,
      songs: overview.tracks,
      artists: overview.artists,
      albums: data
          .ranking(PulseEntityKind.release, PulseMeasure.streams)
          .length,
    );
  }

  static List<WrappedRankedItem> _top(
    PulsePeriodData data,
    PulseEntityDirectory directory,
    PulseEntityKind kind, {
    int limit = topCount,
  }) => [
    for (final entity in data.ranking(kind, PulseMeasure.streams, limit: limit))
      _item(entity, directory),
  ];

  static WrappedRankedItem _item(
    PulseRankedEntity entity,
    PulseEntityDirectory directory,
  ) {
    final info = directory.infoFor(entity.kind, entity.id);
    return WrappedRankedItem(
      rank: entity.rank,
      id: entity.id,
      title: info.title,
      subtitle: info.subtitle,
      streams: entity.metrics.streams,
      listened: entity.metrics.listened,
      status: info.status,
      badge: info.badge,
    );
  }

  /// Genres by streams, highest first (then by name); streams without a
  /// genre are counted apart, never assigned one.
  Future<(List<WrappedGenreShare>, int)> _genres(
    PulsePeriod period,
    int streams,
  ) async {
    if (streams == 0) return (const <WrappedGenreShare>[], 0);
    final counts = <String, int>{};
    final names = <String, String>{};
    var unknown = 0;
    for (final play in await _history.genrePlays(period.window)) {
      final shown = GenreCatalog.display(play.genre);
      if (shown == null) {
        unknown++;
        continue;
      }
      // One bucket per spelling that differs only in case.
      final key = shown.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      final name = names[key];
      if (name == null || shown.compareTo(name) < 0) names[key] = shown;
    }
    final known = counts.values.fold(0, (a, b) => a + b);
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final byStreams = counts[b]!.compareTo(counts[a]!);
        return byStreams != 0 ? byStreams : names[a]!.compareTo(names[b]!);
      });
    return (
      [
        for (final key in keys)
          WrappedGenreShare(
            genre: names[key]!,
            streams: counts[key]!,
            share: counts[key]! / known,
          ),
      ],
      unknown,
    );
  }

  /// Monday-to-Sunday weeks, clipped to the period.
  static List<WrappedActivityPoint> _weeks(PulsePeriodData data) {
    final weeks = <WrappedActivityPoint>[];
    DateTime? start;
    var streams = 0;
    var listened = Duration.zero;
    var recorded = false;
    DateTime? end;
    void close() {
      final weekStart = start;
      if (weekStart == null) return;
      weeks.add(
        WrappedActivityPoint(
          startLocal: weekStart,
          endLocal: end!,
          streams: streams,
          listened: listened,
          recorded: recorded,
        ),
      );
    }

    for (final day in data.days) {
      final date = day.localDate;
      if (start == null || date.weekday == DateTime.monday) {
        close();
        start = date;
        streams = 0;
        listened = Duration.zero;
        recorded = false;
      }
      streams += day.metrics.streams;
      listened += day.metrics.listened;
      recorded = recorded || day.state == PulseDayState.recorded;
      end = DateTime(date.year, date.month, date.day + 1);
    }
    close();
    return List.unmodifiable(weeks);
  }

  /// A year's months, each loaded exactly as its own monthly Wrapped.
  Future<List<WrappedMonthRow>> _months(
    PulsePeriod year,
    PulseEntityDirectory directory,
  ) async {
    final now = _nowLocal();
    final rows = <WrappedMonthRow>[];
    for (var month = 1; month <= 12; month++) {
      final period = PulsePeriod.month(year.year, month);
      if (now.isBefore(period.startLocal)) {
        rows.add(
          WrappedMonthRow(
            period: period,
            state: WrappedPeriodState.future,
            totals: WrappedTotals.zero,
          ),
        );
        continue;
      }
      final data = await _pulse.load(period);
      rows.add(
        WrappedMonthRow(
          period: period,
          state: stateOf(period, data.firstHistoryAt, now),
          totals: totalsOf(data),
          topSong: _top(
            data,
            directory,
            PulseEntityKind.track,
            limit: 1,
          ).firstOrNull,
          topArtist: _top(
            data,
            directory,
            PulseEntityKind.artist,
            limit: 1,
          ).firstOrNull,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  Future<List<WrappedMilestone>> _milestones(
    PulsePeriod period,
    PulsePeriodData data,
  ) async {
    final milestones = <WrappedMilestone>[];

    final streams = data.totals.streams;
    if (streams > 0) {
      final before = await _history.streamsBefore(period.window.startUtc!);
      for (final count in lifetimeMilestones) {
        if (count <= before || count > before + streams) continue;
        final at = await _history.nthStreamAt(count);
        if (at == null) continue;
        milestones.add(
          WrappedMilestone(
            kind: WrappedMilestoneKind.lifetimeStreams,
            value: count,
            atLocal: at.toLocal(),
          ),
        );
      }
    }

    // The longest run of consecutive days with a stream, within the period.
    var bestLength = 0;
    DateTime? bestStart;
    DateTime? bestEnd;
    var length = 0;
    DateTime? runStart;
    for (final day in data.days) {
      if (day.metrics.streams > 0) {
        runStart ??= day.localDate;
        length++;
        if (length > bestLength) {
          bestLength = length;
          bestStart = runStart;
          bestEnd = day.localDate;
        }
      } else {
        length = 0;
        runStart = null;
      }
    }
    if (bestLength >= 2) {
      milestones.add(
        WrappedMilestone(
          kind: WrappedMilestoneKind.longestStreak,
          value: bestLength,
          atLocal: bestStart!,
          untilLocal: bestEnd,
        ),
      );
    }

    PulseDay? busiest;
    for (final day in data.days) {
      if (day.metrics.streams == 0) continue;
      if (busiest == null || day.metrics.streams > busiest.metrics.streams) {
        busiest = day;
      }
    }
    if (busiest != null) {
      milestones.add(
        WrappedMilestone(
          kind: WrappedMilestoneKind.busiestDay,
          value: busiest.metrics.streams,
          atLocal: busiest.localDate,
        ),
      );
    }
    return List.unmodifiable(milestones);
  }

  /// The stored weekly #1s of weeks that ended in [period] (a week belongs
  /// to the period holding its last moment), and how many such weeks.
  Future<(List<WrappedChartNumberOne>, int)> _numberOnes(
    PulsePeriod period,
  ) async {
    final weeks = [
      for (final leader in await _history.weeklyNumberOnes())
        if (_endsIn(period, leader)) leader,
    ];
    final bySong = <String, List<WrappedChartLeader>>{};
    for (final week in weeks) {
      bySong.putIfAbsent(week.songId, () => []).add(week);
    }
    final songs = bySong.values.toList()
      ..sort((a, b) {
        final byWeeks = b.length.compareTo(a.length);
        return byWeeks != 0
            ? byWeeks
            : a.first.weekStartUtc.compareTo(b.first.weekStartUtc);
      });
    return (
      [
        for (final song in songs)
          WrappedChartNumberOne(
            songId: song.first.songId,
            title: song.last.title,
            artistName: song.last.artistName,
            weeks: song.length,
            firstWeekStartLocal: song.first.weekStartUtc.toLocal(),
          ),
      ],
      weeks.length,
    );
  }

  static bool _endsIn(PulsePeriod period, WrappedChartLeader week) {
    final last = week.weekEndUtc
        .subtract(const Duration(microseconds: 1))
        .toLocal();
    return !last.isBefore(period.startLocal) && last.isBefore(period.endLocal);
  }
}
