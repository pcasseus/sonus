// ignore_for_file: prefer_initializing_formals

import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_week.dart';
import '../../domain/repositories/chart_repository.dart';
import '../../domain/services/chart_week_resolver.dart';
import 'chart_snapshot_builder_service.dart';

class ChartFinalizationService {
  const ChartFinalizationService({
    required ChartSnapshotBuilderService builder,
    required ChartRepository charts,
    required QualifiedPlayRepository qualifiedPlays,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
  }) : _builder = builder,
       _charts = charts,
       _qualifiedPlays = qualifiedPlays,
       _weekResolver = weekResolver;

  final ChartSnapshotBuilderService _builder;
  final ChartRepository _charts;
  final QualifiedPlayRepository _qualifiedPlays;
  final ChartWeekResolver _weekResolver;

  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async {
    final currentWeek = _weekResolver.resolve(referenceLocal);

    final plays = await _qualifiedPlays.getAll(
      qualifiedBefore: currentWeek.startUtc,
    );

    final weeksByStartUtc = <String, ChartWeek>{};

    for (final play in plays) {
      final week = _weekResolver.resolve(play.qualifiedAt.toLocal());

      if (!week.startUtc.isBefore(currentWeek.startUtc)) {
        continue;
      }

      weeksByStartUtc[week.startUtc.toIso8601String()] = week;
    }

    final weeks = weeksByStartUtc.values.toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));

    final results = <ChartSnapshot>[];

    for (final week in weeks) {
      results.addAll(await reconcileCompletedWeek(week));
    }

    return List<ChartSnapshot>.unmodifiable(results);
  }

  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) {
    final previousWeekReference = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day - 7,
      12,
    );

    final week = _weekResolver.resolve(previousWeekReference);

    return reconcileCompletedWeek(week);
  }

  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) async {
    final results = <ChartSnapshot>[];

    for (final chartType in ChartType.values) {
      results.add(await _reconcileType(chartType: chartType, week: week));
    }

    return List<ChartSnapshot>.unmodifiable(results);
  }

  Future<ChartSnapshot> _reconcileType({
    required ChartType chartType,
    required ChartWeek week,
  }) async {
    final existing = await _charts.getForWeek(
      chartType: chartType,
      weekStartUtc: week.startUtc,
    );

    final candidate = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      finalizedAt: week.endUtc,
      revision: existing == null ? 1 : existing.revision + 1,
    );

    if (existing != null && _sameChartContent(existing, candidate)) {
      return existing;
    }

    await _charts.replaceSnapshot(candidate);

    return candidate;
  }

  static bool _sameChartContent(
    ChartSnapshot existing,
    ChartSnapshot candidate,
  ) {
    if (existing.id != candidate.id ||
        existing.chartType != candidate.chartType ||
        existing.weekStartUtc.toUtc() != candidate.weekStartUtc.toUtc() ||
        existing.weekEndUtc.toUtc() != candidate.weekEndUtc.toUtc() ||
        existing.entries.length != candidate.entries.length) {
      return false;
    }

    for (var index = 0; index < existing.entries.length; index++) {
      if (!_sameEntry(existing.entries[index], candidate.entries[index])) {
        return false;
      }
    }

    return true;
  }

  static bool _sameEntry(ChartEntry existing, ChartEntry candidate) {
    return existing.entity.entityId == candidate.entity.entityId &&
        existing.entity.title == candidate.entity.title &&
        existing.entity.artistName == candidate.entity.artistName &&
        existing.entity.albumTitle == candidate.entity.albumTitle &&
        existing.rank == candidate.rank &&
        existing.qualifiedStreamCount == candidate.qualifiedStreamCount &&
        existing.lastQualifiedAt.toUtc() == candidate.lastQualifiedAt.toUtc() &&
        existing.previousFinalRank == candidate.previousFinalRank &&
        existing.peakRank == candidate.peakRank &&
        existing.peakAchievedAt.toUtc() == candidate.peakAchievedAt.toUtc() &&
        existing.weeksOnChart == candidate.weeksOnChart &&
        existing.movement == candidate.movement;
  }
}
