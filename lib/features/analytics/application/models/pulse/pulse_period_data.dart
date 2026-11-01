// ignore_for_file: prefer_initializing_formals

import '../analytics_behavior_metrics.dart';
import 'pulse_period.dart';

/// What a Pulse number counts. Never mixed in one value (rule 1):
/// - [minutes]: audible time from listening segments, any length of play;
/// - [streams]: qualified plays (the chart "stream");
/// - [allPlays]: sessions that played audibly at all (excludes failed loads).
enum PulseMeasure { minutes, streams, allPlays }

/// Totals of the three measures. [listened] is exact; minutes are derived.
class PulseMetrics {
  const PulseMetrics({
    required this.listened,
    required this.streams,
    required this.allPlays,
  });

  static const zero = PulseMetrics(
    listened: Duration.zero,
    streams: 0,
    allPlays: 0,
  );

  final Duration listened;
  final int streams;
  final int allPlays;

  bool get isEmpty =>
      listened == Duration.zero && streams == 0 && allPlays == 0;

  /// The value of [measure], minutes as a fraction.
  num valueOf(PulseMeasure measure) => switch (measure) {
    PulseMeasure.minutes =>
      listened.inMilliseconds / Duration.millisecondsPerMinute,
    PulseMeasure.streams => streams,
    PulseMeasure.allPlays => allPlays,
  };

  @override
  bool operator ==(Object other) =>
      other is PulseMetrics &&
      other.listened == listened &&
      other.streams == streams &&
      other.allPlays == allPlays;

  @override
  int get hashCode => Object.hash(listened, streams, allPlays);

  @override
  String toString() =>
      'PulseMetrics(${listened.inMilliseconds} ms, $streams streams, '
      '$allPlays plays)';
}

/// The six overview numbers (spec §4). Active days are days with at least
/// one qualified stream, as in the existing Insights; artists and tracks
/// are distinct lead artists and songs streamed.
class PulseOverview {
  const PulseOverview({
    required this.listened,
    required this.streams,
    required this.allPlays,
    required this.activeDays,
    required this.artists,
    required this.tracks,
  });

  final Duration listened;
  final int streams;
  final int allPlays;
  final int activeDays;
  final int artists;
  final int tracks;

  static const zero = PulseOverview(
    listened: Duration.zero,
    streams: 0,
    allPlays: 0,
    activeDays: 0,
    artists: 0,
    tracks: 0,
  );
}

/// Whether a day can hold data, so "no history" and "not yet" are never
/// drawn as zero (rule 2).
enum PulseDayState {
  /// Before the first recorded session: nothing could have been recorded.
  beforeHistory,

  /// Recorded history (possibly zero).
  recorded,

  /// After today.
  future,
}

/// One local calendar day of a period.
class PulseDay {
  const PulseDay({
    required this.localDate,
    required this.state,
    required this.metrics,
  });

  final DateTime localDate;
  final PulseDayState state;

  /// Zero unless [state] is [PulseDayState.recorded].
  final PulseMetrics metrics;
}

/// One hour of the local day (0–23), summed over the period. All plays are
/// not bucketed by hour.
class PulseHour {
  const PulseHour({
    required this.hour,
    required this.listened,
    required this.streams,
  });

  final int hour;
  final Duration listened;
  final int streams;
}

/// What a ranking ranks. Artists are lead artists after the existing
/// contributor attribution (decision 4); releases are albums by `album_id`,
/// so editions of one release never count twice.
enum PulseEntityKind { track, artist, release }

class PulseRankedEntity {
  const PulseRankedEntity({
    required this.kind,
    required this.id,
    required this.rank,
    required this.metrics,
    required this.lastActivityAt,
  });

  final PulseEntityKind kind;
  final String id;

  /// 1-based, by the measure the ranking was made for.
  final int rank;
  final PulseMetrics metrics;

  /// The latest moment the entity was heard in the period (UTC); breaks ties
  /// in favour of the most recent, as the existing rankings do.
  final DateTime lastActivityAt;
}

/// Why a comparison can or can't be shown (rule 3).
enum PulseComparisonAvailability {
  available,

  /// The comparison period starts before the first recorded session.
  notEnoughHistory,
}

class PulseComparison {
  const PulseComparison({
    required this.period,
    required this.availability,
    required this.totals,
    this.days,
    this.overview,
  });

  final PulsePeriod period;
  final PulseComparisonAvailability availability;

  /// The comparison period's totals; null unless [availability] is
  /// [PulseComparisonAvailability.available].
  final PulseMetrics? totals;

  /// The comparison period's metrics per local day, aligned with
  /// [period]'s days (day of month, or day of year), for the hero's ghost.
  /// Null unless available.
  final List<PulseMetrics>? days;

  /// The comparison period's overview numbers; null unless available.
  final PulseOverview? overview;

  bool get isAvailable => availability == PulseComparisonAvailability.available;
}

/// Everything the Pulse page shows for one period, from recorded history
/// only. Per-entity values and per-day item contributions come from the same
/// clipped rows as the totals, so an item never exceeds its day.
class PulsePeriodData {
  PulsePeriodData({
    required this.period,
    required this.firstHistoryAt,
    required this.totals,
    required this.days,
    required this.hours,
    required this.previous,
    required this.samePeriodLastYear,
    required this.behavior,
    required Map<PulseEntityKind, Map<String, PulseMetrics>> entityTotals,
    required Map<PulseEntityKind, Map<String, DateTime>> entityLastActivity,
    required Map<PulseEntityKind, Map<String, Map<DateTime, PulseMetrics>>>
    entityDays,
    required Set<String> releasesOffRankings,
  }) : _entityTotals = entityTotals,
       _entityLastActivity = entityLastActivity,
       _entityDays = entityDays,
       _releasesOffRankings = releasesOffRankings;

  final PulsePeriod period;

  /// The first recorded session on this device's history (UTC), or null
  /// when nothing was ever recorded.
  final DateTime? firstHistoryAt;
  final PulseMetrics totals;
  final List<PulseDay> days;

  /// 24 entries.
  final List<PulseHour> hours;
  final PulseComparison previous;
  final PulseComparison samePeriodLastYear;

  /// The existing behaviour statistics for the period (completion and skip
  /// rates, active days, peak day), kept for "More about this period".
  final AnalyticsBehaviorMetrics? behavior;

  final Map<PulseEntityKind, Map<String, PulseMetrics>> _entityTotals;
  final Map<PulseEntityKind, Map<String, DateTime>> _entityLastActivity;
  final Map<PulseEntityKind, Map<String, Map<DateTime, PulseMetrics>>>
  _entityDays;
  final Set<String> _releasesOffRankings;

  /// Whether the period starts before recorded history ("History starts
  /// …"); true when there is no history at all.
  bool get startsBeforeHistory {
    final first = firstHistoryAt;
    if (first == null) return true;
    return period.startLocal.isBefore(_localDay(first));
  }

  /// [kind]'s entities ranked by [measure], highest first; ties go to the
  /// most recently heard, then by id. Entities with no [measure] value are
  /// left out. Release rankings hold Albums & EPs only (decision 2).
  List<PulseRankedEntity> ranking(
    PulseEntityKind kind,
    PulseMeasure measure, {
    int? limit,
  }) {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final totals = _entityTotals[kind] ?? const {};
    final last = _entityLastActivity[kind] ?? const {};
    final ids = [
      for (final entry in totals.entries)
        if (entry.value.valueOf(measure) > 0 &&
            !(kind == PulseEntityKind.release &&
                _releasesOffRankings.contains(entry.key)))
          entry.key,
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    ids.sort((a, b) {
      final byValue = totals[b]!
          .valueOf(measure)
          .compareTo(totals[a]!.valueOf(measure));
      if (byValue != 0) return byValue;
      final byRecency = (last[b] ?? epoch).compareTo(last[a] ?? epoch);
      if (byRecency != 0) return byRecency;
      return a.compareTo(b);
    });
    final kept = limit == null || ids.length <= limit
        ? ids
        : ids.sublist(0, limit);
    return List.unmodifiable([
      for (var i = 0; i < kept.length; i++)
        PulseRankedEntity(
          kind: kind,
          id: kept[i],
          rank: i + 1,
          metrics: totals[kept[i]]!,
          lastActivityAt: last[kept[i]] ?? epoch,
        ),
    ]);
  }

  /// The six overview numbers for this period.
  PulseOverview get overview => PulseOverview(
    listened: totals.listened,
    streams: totals.streams,
    allPlays: totals.allPlays,
    activeDays: days.where((d) => d.metrics.streams > 0).length,
    artists: _streamed(PulseEntityKind.artist),
    tracks: _streamed(PulseEntityKind.track),
  );

  int _streamed(PulseEntityKind kind) => (_entityTotals[kind] ?? const {})
      .values
      .where((m) => m.streams > 0)
      .length;

  /// [id]'s totals in the period, or zero.
  PulseMetrics totalsFor(PulseEntityKind kind, String id) =>
      _entityTotals[kind]?[id] ?? PulseMetrics.zero;

  /// [id]'s share of each day, aligned with [days]. Zero on days without the
  /// item; never more than the day's own metrics.
  List<PulseMetrics> daySeriesFor(PulseEntityKind kind, String id) {
    final byDay = _entityDays[kind]?[id] ?? const {};
    return List.unmodifiable([
      for (final day in days) byDay[day.localDate] ?? PulseMetrics.zero,
    ]);
  }

  static DateTime _localDay(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
