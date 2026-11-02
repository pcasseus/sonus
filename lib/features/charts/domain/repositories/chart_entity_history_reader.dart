import '../entities/chart_entry.dart';
import '../models/chart_type.dart';

/// One finalized chart week in which an entity appeared (Top 200).
class ChartEntityWeek {
  const ChartEntityWeek({
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.finalizedAt,
    required this.entry,
  });

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final DateTime finalizedAt;

  /// The entry exactly as it was stored when the week was finalized.
  final ChartEntry entry;
}

/// Read-only access to one entity's finalized chart history (Song Stats).
/// Never writes, rebuilds or reinterprets a stored week.
abstract interface class ChartEntityHistoryReader {
  /// Every finalized [chartType] week in which [entityId] held a stored
  /// position, oldest first.
  Future<List<ChartEntityWeek>> finalizedWeeksFor(
    ChartType chartType,
    String entityId,
  );
}
