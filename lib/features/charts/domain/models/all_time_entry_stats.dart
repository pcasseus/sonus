import '../services/all_time_history_replay.dart';

/// Extra statistics for one all-time chart entry.
class AllTimeEntryStats {
  const AllTimeEntryStats({
    this.streamsThisWeek = 0,
    this.streamsSameTimeLastWeek = 0,
    this.zones = const ZoneWeeks({}),
  });

  /// Qualified plays since this chart week began.
  final int streamsThisWeek;

  /// Qualified plays over the same stretch of last week, so a week in
  /// progress is never compared with a whole week.
  final int streamsSameTimeLastWeek;

  /// Completed weeks spent in each zone of the all-time chart.
  final ZoneWeeks zones;

  /// Percentage change against the same time last week, or null when there
  /// is nothing to compare with.
  double? get weeklyChangePercent => streamsSameTimeLastWeek == 0
      ? null
      : (streamsThisWeek - streamsSameTimeLastWeek) *
            100 /
            streamsSameTimeLastWeek;

  /// Played this week after no plays at the same time last week.
  bool get isNewActivity => streamsSameTimeLastWeek == 0 && streamsThisWeek > 0;
}
