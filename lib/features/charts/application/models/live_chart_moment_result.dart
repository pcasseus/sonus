import '../../domain/entities/chart_snapshot.dart';
import '../../domain/moments/chart_moment_event.dart';

class LiveChartMomentResult {
  const LiveChartMomentResult({required this.snapshot, required this.moments});

  final ChartSnapshot snapshot;
  final List<ChartMomentEvent> moments;
}
