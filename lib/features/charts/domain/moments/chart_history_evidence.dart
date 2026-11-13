import '../entities/chart_snapshot.dart';

/// What a finalization pass knows about the chart history behind a week
/// (App Update 1.2, REF-19), so a Moment claims history only when the
/// history is complete and every week in it is known to be original.
class ChartHistoryEvidence {
  const ChartHistoryEvidence({
    required this.currentWeekOriginal,
    this.historyOriginUtc,
    this.incompleteWeekStartsUtc = const {},
  });

  /// Nothing can be shown: no historical claim, no streak.
  static const unverified = ChartHistoryEvidence(currentWeekOriginal: false);

  /// Earlier finalized weeks needed before any first, record or repeat is
  /// claimed: necessary, never sufficient.
  static const int minimumEarlierWeeks = 8;

  /// The week being finalized is original (see [ChartSnapshotProvenance]).
  final bool currentWeekOriginal;

  /// When this database's chart history began; weeks before it were not
  /// all recorded here. Null when unknown.
  final DateTime? historyOriginUtc;

  /// Weeks with qualified plays but no finalized chart, by start.
  final Set<DateTime> incompleteWeekStartsUtc;

  /// True only when [earlierWeeks] (the finalized songs weeks before the
  /// one starting at [currentStartUtc]) are at least
  /// [minimumEarlierWeeks], all original, and no earlier week with plays
  /// lacks its chart.
  bool supportsHistoricalClaims({
    required DateTime currentStartUtc,
    required List<ChartSnapshot> earlierWeeks,
  }) {
    if (!currentWeekOriginal) return false;
    if (earlierWeeks.length < minimumEarlierWeeks) return false;
    if (earlierWeeks.any(
      (week) => week.provenance != ChartSnapshotProvenance.original,
    )) {
      return false;
    }
    return !incompleteWeekStartsUtc.any(
      (start) => start.toUtc().isBefore(currentStartUtc.toUtc()),
    );
  }

  /// The verified history window before the week starting at
  /// [currentStartUtc]: the longest run of original [earlierWeeks] reaching
  /// up to it, with no week of plays missing its chart inside it, oldest
  /// first. Null unless the current week is original and the window holds
  /// at least [minimumEarlierWeeks]. Unknown weeks (stored before version
  /// 46), unverified weeks and weeks with plays but no chart end it: it
  /// never reaches back across them.
  List<ChartSnapshot>? verifiedWindow({
    required DateTime currentStartUtc,
    required List<ChartSnapshot> earlierWeeks,
  }) {
    if (!currentWeekOriginal) return null;
    final current = currentStartUtc.toUtc();
    final weeks = [
      for (final week in earlierWeeks)
        if (week.weekStartUtc.toUtc().isBefore(current)) week,
    ]..sort((a, b) => a.weekStartUtc.compareTo(b.weekStartUtc));
    DateTime? lastGap;
    for (final start in incompleteWeekStartsUtc) {
      final utc = start.toUtc();
      if (!utc.isBefore(current)) continue;
      if (lastGap == null || utc.isAfter(lastGap)) lastGap = utc;
    }
    final window = <ChartSnapshot>[];
    for (final week in weeks.reversed) {
      final start = week.weekStartUtc.toUtc();
      if (lastGap != null && !start.isAfter(lastGap)) break;
      if (week.provenance != ChartSnapshotProvenance.original) break;
      window.add(week);
    }
    if (window.length < minimumEarlierWeeks) return null;
    return List.unmodifiable(window.reversed);
  }

  /// Whether the week ending at [weekEndUtc] provably had no chart: this
  /// database was recording then (it began at or before the week did) and
  /// the week had no plays.
  bool isKnownEmptyWeekBefore(DateTime weekEndUtc) {
    final origin = historyOriginUtc;
    if (origin == null) return false;
    final end = weekEndUtc.toUtc();
    // A Sonus week is seven days, give or take a daylight-saving hour.
    final start = end.subtract(const Duration(days: 7, hours: 1));
    if (start.isBefore(origin.toUtc())) return false;
    return !incompleteWeekStartsUtc.any((s) {
      final week = s.toUtc();
      return !week.isBefore(start) && week.isBefore(end);
    });
  }
}
