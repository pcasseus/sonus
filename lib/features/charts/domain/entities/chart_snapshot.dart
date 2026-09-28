import '../models/chart_type.dart';
import 'chart_entry.dart';

class ChartSnapshot {
  const ChartSnapshot({
    required this.id,
    required this.chartType,
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.entries,
    this.finalizedAt,
    this.revision = 1,
  });

  final String id;
  final ChartType chartType;

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;

  final DateTime? finalizedAt;

  final int revision;

  final List<ChartEntry> entries;

  bool get isFinalized => finalizedAt != null;

  bool get isLive => finalizedAt == null;

  List<ChartEntry> get officialEntries => entries
      .where((entry) => entry.isOfficiallyCharting)
      .toList(growable: false);
}
