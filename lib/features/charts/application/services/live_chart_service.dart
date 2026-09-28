// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../../domain/services/chart_week_resolver.dart';
import 'chart_snapshot_builder_service.dart';

class LiveChartService {
  const LiveChartService({
    required ChartSnapshotBuilderService builder,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
  }) : _builder = builder,
       _weekResolver = weekResolver;

  final ChartSnapshotBuilderService _builder;
  final ChartWeekResolver _weekResolver;

  Future<ChartSnapshot> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async {
    final week = _weekResolver.resolve(referenceLocal);

    final snapshot = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
    );

    if (snapshot.entries.length <= viewSize.limit) {
      return snapshot;
    }

    return ChartSnapshot(
      id: snapshot.id,
      chartType: snapshot.chartType,
      weekStartUtc: snapshot.weekStartUtc,
      weekEndUtc: snapshot.weekEndUtc,
      finalizedAt: snapshot.finalizedAt,
      revision: snapshot.revision,
      entries: List.unmodifiable(snapshot.entries.take(viewSize.limit)),
    );
  }
}
