// ignore_for_file: prefer_initializing_formals

import '../../../../charts/domain/services/release_chart_eligibility.dart';
import '../../models/analytics_behavior_metrics.dart';
import '../../models/analytics_period.dart';
import '../../models/analytics_time_window.dart';
import '../../models/pulse/pulse_period.dart';
import '../../models/pulse/pulse_period_data.dart';
import '../analytics_behavior_metrics_service.dart';
import '../listening_artist_attribution.dart';
import 'pulse_listening_records.dart';

/// Assembles a [PulsePeriodData] from recorded listening only.
///
/// - Minutes: listening segments clipped to the period and split at local
///   hour boundaries (never the qualified-play snapshots).
/// - Streams: qualified plays by qualified time.
/// - All plays: sessions with audible time, by start time.
/// - Every per-entity and per-day-per-entity value is added from the same
///   slice as the day's total, so an item can never exceed its day.
/// - Artists follow the existing lead-artist attribution; releases are
///   `album_id`; Singles are left out of release rankings only.
/// What the Pulse controller needs from the data layer.
abstract interface class PulsePeriodLoader {
  /// The start of the first recorded session (UTC), or null.
  Future<DateTime?> firstHistoryAt();

  Future<PulsePeriodData> load(PulsePeriod period);
}

class PulseInsightsService implements PulsePeriodLoader {
  PulseInsightsService({
    required PulseListeningRecords records,
    ListeningArtistAttribution? artistAttribution,
    ReleaseChartEligibility? releaseEligibility,
    AnalyticsBehaviorMetricsService? behaviorMetrics,
    DateTime Function()? nowLocal,
  }) : _records = records,
       _artistAttribution = artistAttribution,
       _releaseEligibility = releaseEligibility,
       _behaviorMetrics = behaviorMetrics,
       _nowLocal = nowLocal ?? DateTime.now;

  final PulseListeningRecords _records;
  final ListeningArtistAttribution? _artistAttribution;
  final ReleaseChartEligibility? _releaseEligibility;
  final AnalyticsBehaviorMetricsService? _behaviorMetrics;
  final DateTime Function() _nowLocal;

  @override
  Future<DateTime?> firstHistoryAt() => _records.firstSessionStartedAt();

  @override
  Future<PulsePeriodData> load(PulsePeriod period) async {
    final window = period.window;

    final firstFuture = _records.firstSessionStartedAt();
    final segmentsFuture = _records.segmentsOverlapping(window);
    final streamsFuture = _records.qualifiedPlays(window);
    final playsFuture = _records.audibleSessions(window);
    final attributorFuture = ArtistAttributor.of(_artistAttribution);
    final excludedFuture = excludedReleaseIds(_releaseEligibility);
    final behaviorFuture = _loadBehavior(period);

    final first = await firstFuture;
    final segments = await segmentsFuture;
    final streams = await streamsFuture;
    final plays = await playsFuture;
    final attributor = await attributorFuture;
    final excluded = await excludedFuture;
    final behavior = await behaviorFuture;

    final acc = _Accumulator(attributor);

    for (final segment in segments) {
      _sliceSegment(segment, window, (sliceEnd, localDay, localHour, ms) {
        acc.addListening(
          segment: segment,
          day: localDay,
          hour: localHour,
          milliseconds: ms,
          at: sliceEnd,
        );
      });
    }
    for (final play in streams) {
      if (!window.contains(play.at)) continue;
      final local = play.at.toLocal();
      acc.addStream(play, _dayOf(local), local.hour);
    }
    for (final play in plays) {
      if (!window.contains(play.at)) continue;
      acc.addPlay(play, _dayOf(play.at.toLocal()));
    }

    final today = _dayOf(_nowLocal());
    final firstDay = first == null ? null : _dayOf(first.toLocal());
    final days = [
      for (final day in period.days)
        _day(day, acc.days[day], today: today, firstDay: firstDay),
    ];

    final previous = await _comparison(period.previous, firstDay);
    final sameLastYear = period.samePeriodLastYear == period.previous
        ? previous
        : await _comparison(period.samePeriodLastYear, firstDay);

    return PulsePeriodData(
      period: period,
      firstHistoryAt: first,
      totals: acc.totals.freeze(),
      days: List.unmodifiable(days),
      hours: List.unmodifiable([
        for (var hour = 0; hour < 24; hour++)
          PulseHour(
            hour: hour,
            listened: Duration(milliseconds: acc.hourMilliseconds[hour]),
            streams: acc.hourStreams[hour],
          ),
      ]),
      previous: previous,
      samePeriodLastYear: sameLastYear,
      behavior: behavior,
      entityTotals: {
        for (final kind in PulseEntityKind.values)
          kind: {
            for (final entry in acc.entities[kind]!.entries)
              entry.key: entry.value.freeze(),
          },
      },
      entityLastActivity: {
        for (final kind in PulseEntityKind.values)
          kind: Map.of(acc.lastActivity[kind]!),
      },
      entityDays: {
        for (final kind in PulseEntityKind.values)
          kind: {
            for (final entry in acc.entityDays[kind]!.entries)
              entry.key: {
                for (final day in entry.value.entries)
                  day.key: day.value.freeze(),
              },
          },
      },
      releasesOffRankings: excluded,
    );
  }

  /// Totals of [period] alone, for comparisons.
  Future<PulseMetrics> totalsFor(PulsePeriod period) async {
    final days = await dailyTotalsFor(period);
    var listened = Duration.zero;
    var streams = 0;
    var allPlays = 0;
    for (final day in days) {
      listened += day.listened;
      streams += day.streams;
      allPlays += day.allPlays;
    }
    return PulseMetrics(
      listened: listened,
      streams: streams,
      allPlays: allPlays,
    );
  }

  /// [period]'s metrics per local day, aligned with [PulsePeriod.days], by
  /// the same slicing as [load].
  Future<List<PulseMetrics>> dailyTotalsFor(PulsePeriod period) async {
    final window = period.window;
    final segmentsFuture = _records.segmentsOverlapping(window);
    final streamsFuture = _records.qualifiedPlays(window);
    final playsFuture = _records.audibleSessions(window);

    final days = <DateTime, _MutableMetrics>{};
    _MutableMetrics dayOf(DateTime day) =>
        days.putIfAbsent(day, _MutableMetrics.new);

    for (final segment in await segmentsFuture) {
      _sliceSegment(segment, window, (_, localDay, _, ms) {
        dayOf(localDay).milliseconds += ms;
      });
    }
    for (final play in await streamsFuture) {
      if (window.contains(play.at)) dayOf(_dayOf(play.at.toLocal())).streams++;
    }
    for (final play in await playsFuture) {
      if (window.contains(play.at)) {
        dayOf(_dayOf(play.at.toLocal())).allPlays++;
      }
    }
    return List.unmodifiable([
      for (final day in period.days) days[day]?.freeze() ?? PulseMetrics.zero,
    ]);
  }

  /// Rule 3: a comparison needs the whole comparison period inside recorded
  /// history. Judged by local day: a period that starts on the day of the
  /// first recorded session is eligible; one that starts earlier is not.
  static bool comparisonEligible(PulsePeriod comparison, DateTime? firstDay) =>
      firstDay != null && !comparison.startLocal.isBefore(firstDay);

  Future<PulseComparison> _comparison(
    PulsePeriod comparison,
    DateTime? firstDay,
  ) async {
    if (!comparisonEligible(comparison, firstDay)) {
      return PulseComparison(
        period: comparison,
        availability: PulseComparisonAvailability.notEnoughHistory,
        totals: null,
      );
    }
    final days = await dailyTotalsFor(comparison);
    var listened = Duration.zero;
    var streams = 0;
    var allPlays = 0;
    for (final day in days) {
      listened += day.listened;
      streams += day.streams;
      allPlays += day.allPlays;
    }
    return PulseComparison(
      period: comparison,
      availability: PulseComparisonAvailability.available,
      totals: PulseMetrics(
        listened: listened,
        streams: streams,
        allPlays: allPlays,
      ),
      days: days,
    );
  }

  Future<AnalyticsBehaviorMetrics?> _loadBehavior(PulsePeriod period) async {
    final service = _behaviorMetrics;
    if (service == null) return null;
    return service.load(
      period: switch (period.kind) {
        PulsePeriodKind.month => AnalyticsPeriod.month,
        PulsePeriodKind.year => AnalyticsPeriod.year,
      },
      referenceLocal: period.startLocal,
    );
  }

  PulseDay _day(
    DateTime day,
    _MutableMetrics? metrics, {
    required DateTime today,
    required DateTime? firstDay,
  }) {
    // Recorded data always shows, even on a day the clock calls future.
    if (metrics != null && !metrics.isEmpty) {
      return PulseDay(
        localDate: day,
        state: PulseDayState.recorded,
        metrics: metrics.freeze(),
      );
    }
    final state = day.isAfter(today)
        ? PulseDayState.future
        : (firstDay == null || day.isBefore(firstDay))
        ? PulseDayState.beforeHistory
        : PulseDayState.recorded;
    return PulseDay(localDate: day, state: state, metrics: PulseMetrics.zero);
  }

  /// Splits [segment]'s part inside [window] at local hour boundaries.
  static void _sliceSegment(
    PulseSegmentRecord segment,
    AnalyticsTimeWindow window,
    void Function(DateTime sliceEnd, DateTime localDay, int hour, int ms) add,
  ) {
    final start = _later(segment.startedAt.toUtc(), window.startUtc);
    final end = _earlier(segment.truthfulEnd, window.endUtc);
    var cursor = start;
    while (cursor.isBefore(end)) {
      final local = cursor.toLocal();
      final nextHour = DateTime(
        local.year,
        local.month,
        local.day,
        local.hour + 1,
      ).toUtc();
      final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
      if (!sliceEnd.isAfter(cursor)) break;
      add(
        sliceEnd,
        _dayOf(local),
        local.hour,
        sliceEnd.difference(cursor).inMilliseconds,
      );
      cursor = sliceEnd;
    }
  }

  static DateTime _dayOf(DateTime local) =>
      DateTime(local.year, local.month, local.day);

  static DateTime _later(DateTime a, DateTime? b) =>
      b != null && a.isBefore(b) ? b : a;

  static DateTime _earlier(DateTime a, DateTime? b) =>
      b != null && a.isAfter(b) ? b : a;
}

class _MutableMetrics {
  int milliseconds = 0;
  int streams = 0;
  int allPlays = 0;

  bool get isEmpty => milliseconds == 0 && streams == 0 && allPlays == 0;

  PulseMetrics freeze() => PulseMetrics(
    listened: Duration(milliseconds: milliseconds),
    streams: streams,
    allPlays: allPlays,
  );
}

class _Accumulator {
  _Accumulator(this._attributor);

  final ArtistAttributor _attributor;

  final totals = _MutableMetrics();
  final days = <DateTime, _MutableMetrics>{};
  final hourMilliseconds = List<int>.filled(24, 0);
  final hourStreams = List<int>.filled(24, 0);
  final entities = {
    for (final kind in PulseEntityKind.values)
      kind: <String, _MutableMetrics>{},
  };
  final entityDays = {
    for (final kind in PulseEntityKind.values)
      kind: <String, Map<DateTime, _MutableMetrics>>{},
  };
  final lastActivity = {
    for (final kind in PulseEntityKind.values) kind: <String, DateTime>{},
  };

  void addListening({
    required PulseSegmentRecord segment,
    required DateTime day,
    required int hour,
    required int milliseconds,
    required DateTime at,
  }) {
    totals.milliseconds += milliseconds;
    _dayOf(day).milliseconds += milliseconds;
    hourMilliseconds[hour] += milliseconds;
    _forEntities(segment.songId, segment.artistId, segment.albumId, day, at, (
      metrics,
    ) {
      metrics.milliseconds += milliseconds;
    });
  }

  void addStream(PulsePlayRecord play, DateTime day, int hour) {
    totals.streams++;
    _dayOf(day).streams++;
    hourStreams[hour]++;
    _forEntities(play.songId, play.artistId, play.albumId, day, play.at, (
      metrics,
    ) {
      metrics.streams++;
    });
  }

  void addPlay(PulsePlayRecord play, DateTime day) {
    totals.allPlays++;
    _dayOf(day).allPlays++;
    _forEntities(play.songId, play.artistId, play.albumId, day, play.at, (
      metrics,
    ) {
      metrics.allPlays++;
    });
  }

  _MutableMetrics _dayOf(DateTime day) =>
      days.putIfAbsent(day, _MutableMetrics.new);

  void _forEntities(
    String songId,
    String artistId,
    String albumId,
    DateTime day,
    DateTime at,
    void Function(_MutableMetrics) add,
  ) {
    final ids = {
      PulseEntityKind.track: songId,
      PulseEntityKind.artist: _attributor.artistFor(
        artistId: artistId,
        albumId: albumId,
      ),
      PulseEntityKind.release: albumId,
    };
    for (final MapEntry(key: kind, value: id) in ids.entries) {
      add(entities[kind]!.putIfAbsent(id, _MutableMetrics.new));
      add(
        entityDays[kind]!
            .putIfAbsent(id, () => <DateTime, _MutableMetrics>{})
            .putIfAbsent(day, _MutableMetrics.new),
      );
      final utc = at.toUtc();
      final last = lastActivity[kind]![id];
      if (last == null || utc.isAfter(last)) lastActivity[kind]![id] = utc;
    }
  }
}
