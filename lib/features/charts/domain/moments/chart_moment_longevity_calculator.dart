import '../entities/chart_snapshot.dart';
import 'chart_moment_finalized_detector.dart';
import 'chart_moment_longevity_state.dart';

class ChartMomentLongevityCalculator {
  const ChartMomentLongevityCalculator();

  ChartMomentLongevityState calculate({
    required String entityId,
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Chart longevity requires a finalized snapshot.',
      );
    }

    final currentWeekStart = snapshot.weekStartUtc.toUtc();

    final snapshots = <ChartSnapshot>[
      ...history.where(
        (historical) =>
            historical.isFinalized &&
            historical.chartType == snapshot.chartType &&
            historical.weekStartUtc.toUtc().isBefore(currentWeekStart),
      ),
      snapshot,
    ]..sort((a, b) => a.weekStartUtc.toUtc().compareTo(b.weekStartUtc.toUtc()));

    final appearances = <_Appearance>[];

    for (final historical in snapshots) {
      final matching = historical.entries
          .where((entry) => entry.entity.entityId == entityId)
          .toList(growable: false);

      if (matching.length > 1) {
        throw StateError(
          'Duplicate chart entries exist for $entityId during '
          '${historical.weekStartUtc.toUtc().toIso8601String()}.',
        );
      }

      if (matching.isEmpty) {
        continue;
      }

      appearances.add(
        _Appearance(
          weekStartUtc: historical.weekStartUtc.toUtc(),
          weekEndUtc: historical.weekEndUtc.toUtc(),
          rank: matching.single.rank,
        ),
      );
    }

    final totalThresholdWeeks = <int, int>{};
    final consecutiveThresholdWeeks = <int, int>{};

    for (final threshold in ChartMomentFinalizedDetector.thresholds) {
      totalThresholdWeeks[threshold] = appearances
          .where((appearance) => appearance.rank <= threshold)
          .length;

      consecutiveThresholdWeeks[threshold] = _consecutiveEndingAtCurrentWeek(
        appearances.where((appearance) => appearance.rank <= threshold),
        currentWeekStart,
      );
    }

    return ChartMomentLongevityState(
      totalChartWeeks: appearances.length,
      consecutiveChartWeeks: _consecutiveEndingAtCurrentWeek(
        appearances,
        currentWeekStart,
      ),
      totalThresholdWeeks: Map<int, int>.unmodifiable(totalThresholdWeeks),
      consecutiveThresholdWeeks: Map<int, int>.unmodifiable(
        consecutiveThresholdWeeks,
      ),
    );
  }

  static int _consecutiveEndingAtCurrentWeek(
    Iterable<_Appearance> source,
    DateTime currentWeekStartUtc,
  ) {
    final appearances = source.toList(growable: false)
      ..sort((a, b) => b.weekStartUtc.compareTo(a.weekStartUtc));

    if (appearances.isEmpty ||
        appearances.first.weekStartUtc != currentWeekStartUtc) {
      return 0;
    }

    var count = 1;
    var expectedPreviousEnd = appearances.first.weekStartUtc;

    for (final appearance in appearances.skip(1)) {
      if (appearance.weekEndUtc != expectedPreviousEnd) {
        break;
      }

      count++;
      expectedPreviousEnd = appearance.weekStartUtc;
    }

    return count;
  }
}

class _Appearance {
  const _Appearance({
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.rank,
  });

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final int rank;
}
