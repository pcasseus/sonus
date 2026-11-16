import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';

/// One finalized week of an entity's weekly chart history: its position
/// that week, or null when it was not on that week's chart.
typedef ChartTrendWeek = ({DateTime weekStartUtc, int? rank});

/// An entity's positions on the finalized weekly chart over its most recent
/// weeks (App Update 1.3 Chart Studio). Built only from stored finalized
/// weeks: the provisional week in progress is never part of it, and a week
/// the entity missed stays a gap rather than an invented point.
class ChartRankTrend {
  const ChartRankTrend._(this.weeks);

  /// The most weeks a trend covers.
  static const int maxWeeks = 8;

  /// The trend for [entityId] over the finalized [history] of [chartType],
  /// ending with the week starting [throughWeekStartUtc] (the latest
  /// finalized week when null). Null when fewer than two of those weeks
  /// have a position, as a line through one point would mislead.
  static ChartRankTrend? of(
    List<ChartSnapshot> history, {
    required ChartType chartType,
    required String entityId,
    DateTime? throughWeekStartUtc,
  }) {
    final through = throughWeekStartUtc?.toUtc();
    final weeks = [
      for (final snapshot in history)
        if (snapshot.isFinalized &&
            snapshot.chartType == chartType &&
            (through == null ||
                !snapshot.weekStartUtc.toUtc().isAfter(through)))
          snapshot,
    ]..sort((a, b) => a.weekStartUtc.compareTo(b.weekStartUtc));
    final recent = weeks.length > maxWeeks
        ? weeks.sublist(weeks.length - maxWeeks)
        : weeks;

    final points = [
      for (final week in recent)
        (
          weekStartUtc: week.weekStartUtc.toUtc(),
          rank: _rankIn(week, entityId),
        ),
    ];
    final charted = points.where((p) => p.rank != null).length;
    return charted < 2 ? null : ChartRankTrend._(List.unmodifiable(points));
  }

  static int? _rankIn(ChartSnapshot week, String entityId) {
    for (final entry in week.entries) {
      if (entry.entity.entityId == entityId) return entry.rank;
    }
    return null;
  }

  /// Oldest first.
  final List<ChartTrendWeek> weeks;

  /// The best (lowest) position in the trend.
  int get bestRank =>
      weeks.map((w) => w.rank).whereType<int>().reduce((a, b) => a < b ? a : b);

  /// The position in the most recent week, or null when it missed that week.
  int? get latestRank => weeks.last.rank;

  /// For screen readers: every week in order.
  String get spokenLabel => [
    'Weekly chart positions over the last ${weeks.length} finalized weeks',
    for (final week in weeks)
      week.rank == null ? 'not on the chart' : 'number ${week.rank}',
  ].join(', ');
}
