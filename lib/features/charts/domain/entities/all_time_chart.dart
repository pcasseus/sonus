import '../models/all_time_entry_stats.dart';
import '../models/chart_type.dart';
import 'chart_entry.dart';

/// The permanent Hot 100 (and its Top 200 standings): cumulative qualified
/// plays since listening began. It is computed, never stored.
///
/// Entries reuse [ChartEntry]. On this chart `previousFinalRank` is the
/// all-time rank at [comparisonStartUtc], and `weeksOnChart` is always 0.
class AllTimeChart {
  const AllTimeChart({
    required this.chartType,
    required this.comparisonStartUtc,
    required this.entries,
    this.stats = const {},
  });

  final ChartType chartType;

  /// Start of the current chart week; movement is measured from here.
  final DateTime comparisonStartUtc;

  final List<ChartEntry> entries;

  /// Weekly change and weeks in zones, by entity id.
  final Map<String, AllTimeEntryStats> stats;

  AllTimeEntryStats statsFor(ChartEntry entry) =>
      stats[entry.entity.entityId] ?? const AllTimeEntryStats();
}
