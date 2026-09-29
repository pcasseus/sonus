import '../../../analytics/domain/entities/qualified_play.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_type.dart';

class ChartMomentLifetimeStreamService {
  const ChartMomentLifetimeStreamService({required this._qualifiedPlays});

  final QualifiedPlayRepository _qualifiedPlays;

  Future<Map<String, int>> load({required ChartSnapshot snapshot}) async {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Lifetime stream state requires a finalized chart snapshot.',
      );
    }

    return await loadBefore(
      chartType: snapshot.chartType,
      qualifiedBeforeUtc: snapshot.weekEndUtc,
    );
  }

  Future<Map<String, int>> loadBefore({
    required ChartType chartType,
    required DateTime qualifiedBeforeUtc,
  }) async {
    final plays = await _qualifiedPlays.getAll(
      qualifiedBefore: qualifiedBeforeUtc.toUtc(),
    );

    final totals = <String, int>{};

    for (final play in plays) {
      final entityId = _entityIdFor(play: play, chartType: chartType);

      totals.update(entityId, (current) => current + 1, ifAbsent: () => 1);
    }

    return Map<String, int>.unmodifiable(totals);
  }

  static String _entityIdFor({
    required QualifiedPlay play,
    required ChartType chartType,
  }) {
    switch (chartType) {
      case ChartType.songs:
        return play.songId;

      case ChartType.albums:
        return play.albumId;
    }
  }
}
