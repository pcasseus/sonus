// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../../domain/services/release_chart_eligibility.dart';
import 'chart_snapshot_builder_service.dart';

/// The chart week in progress, built in memory and never stored.
class ProvisionalWeekChart {
  ProvisionalWeekChart({
    required this.snapshot,
    required Map<String, int> bestSoFarRanks,
  }) : _bestSoFarRanks = Map.unmodifiable(bestSoFarRanks);

  /// Not finalized: [ChartSnapshot.finalizedAt] is null.
  final ChartSnapshot snapshot;

  final Map<String, int> _bestSoFarRanks;

  /// The best position the entity has held so far this week. Provisional:
  /// never a career peak until a finalized week confirms it (SN-50 E-Q18).
  int? bestSoFarRank(String entityId) => _bestSoFarRanks[entityId];
}

/// SN-50 E-Q5: the provisional This Week chart. It ranks like a finalized
/// week, with the same eligibility, and compares with the previous
/// finalized week. It never writes chart history or Moments.
class ThisWeekChartService {
  const ThisWeekChartService({
    required ChartSnapshotBuilderService builder,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    ReleaseChartEligibility? releaseEligibility,
  }) : _builder = builder,
       _weekResolver = weekResolver,
       _releaseEligibility = releaseEligibility;

  final ChartSnapshotBuilderService _builder;
  final ChartWeekResolver _weekResolver;
  final ReleaseChartEligibility? _releaseEligibility;

  Future<ProvisionalWeekChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
  }) async {
    final week = _weekResolver.resolve(referenceLocal);
    final bestSoFar = <String, int>{};

    final snapshot = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      excludedAlbumIds: chartType == ChartType.albums
          ? await excludedReleaseIds(_releaseEligibility)
          : const {},
      onRankObservation: (observation) {
        final rank = observation.currentRank;
        if (rank == null) return;
        final best = bestSoFar[observation.entityId];
        if (best == null || rank < best) {
          bestSoFar[observation.entityId] = rank;
        }
      },
    );

    return ProvisionalWeekChart(snapshot: snapshot, bestSoFarRanks: bestSoFar);
  }
}
