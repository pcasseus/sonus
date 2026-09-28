import '../entities/chart_snapshot.dart';
import '../models/chart_type.dart';

abstract interface class ChartRepository {
  Future<void> replaceSnapshot(ChartSnapshot snapshot);

  Future<ChartSnapshot?> getById(String id);

  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  });

  Future<List<ChartSnapshot>> getHistory(ChartType chartType, {int? limit});
}
