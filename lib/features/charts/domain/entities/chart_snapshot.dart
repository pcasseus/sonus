import '../models/chart_type.dart';
import 'chart_entry.dart';

/// How a finalized week came to be stored (App Update 1.2, REF-19; local
/// database version 46). Historical claims ("the first ... in Sonus Hot 100
/// history") trust only [original] weeks.
enum ChartSnapshotProvenance {
  /// Finalized by this database from plays it recorded itself, for a week
  /// that began after its chart history did (see `chart_history_origin`)
  /// and was never recalculated after a deletion or merge.
  original,

  /// Anything else: rebuilt after a deletion or merge, after a restore, from
  /// plays synced to a new install, or for a week already under way when
  /// version 46 arrived. Kept, shown and charted as usual; never used as
  /// evidence for a historical claim.
  unverified;

  static ChartSnapshotProvenance? fromName(Object? name) =>
      values.where((value) => value.name == name).firstOrNull;
}

class ChartSnapshot {
  const ChartSnapshot({
    required this.id,
    required this.chartType,
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.entries,
    this.finalizedAt,
    this.revision = 1,
    this.provenance,
  });

  final String id;
  final ChartType chartType;

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;

  final DateTime? finalizedAt;

  final int revision;

  final List<ChartEntry> entries;

  /// Null when unknown: stored before version 46, or restored from a
  /// backup made before it. Unknown is never treated as [original].
  final ChartSnapshotProvenance? provenance;

  ChartSnapshot withProvenance(ChartSnapshotProvenance? provenance) =>
      ChartSnapshot(
        id: id,
        chartType: chartType,
        weekStartUtc: weekStartUtc,
        weekEndUtc: weekEndUtc,
        entries: entries,
        finalizedAt: finalizedAt,
        revision: revision,
        provenance: provenance,
      );

  bool get isFinalized => finalizedAt != null;

  bool get isLive => finalizedAt == null;

  List<ChartEntry> get officialEntries => entries
      .where((entry) => entry.isOfficiallyCharting)
      .toList(growable: false);
}
