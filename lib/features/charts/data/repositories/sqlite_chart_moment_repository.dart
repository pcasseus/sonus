import '../../../../core/database/app_database.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../daos/chart_moment_event_dao.dart';
import '../mappers/chart_moment_event_row_mapper.dart';

class SqliteChartMomentRepository implements ChartMomentRepository {
  const SqliteChartMomentRepository(this.database);

  final AppDatabase database;

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) {
    return database.transaction((transaction) async {
      final dao = ChartMomentEventDao(transaction);

      for (final event in events) {
        await dao.insertIgnoreDuplicate(ChartMomentEventRowMapper.toRow(event));
      }
    });
  }

  @override
  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async {
    final normalizedWeekStartUtc = weekStartUtc.toUtc();
    final replacement = List<ChartMomentEvent>.unmodifiable(events);

    for (final event in replacement) {
      if (event.scope != ChartMomentScope.finalized) {
        throw ArgumentError.value(
          event.scope,
          'events',
          'FINAL Moment replacement cannot contain live events.',
        );
      }

      if (event.chartType != chartType) {
        throw ArgumentError.value(
          event.chartType,
          'events',
          'FINAL Moment replacement cannot contain another chart type.',
        );
      }

      if (event.weekStartUtc.toUtc() != normalizedWeekStartUtc) {
        throw ArgumentError.value(
          event.weekStartUtc,
          'events',
          'FINAL Moment replacement cannot contain another chart week.',
        );
      }
    }

    await database.transaction((transaction) async {
      final dao = ChartMomentEventDao(transaction);

      await dao.deleteFinalizedForWeek(
        chartType: chartType.name,
        weekStartUtc: normalizedWeekStartUtc,
      );

      for (final event in replacement) {
        await dao.insertIgnoreDuplicate(ChartMomentEventRowMapper.toRow(event));
      }
    });
  }

  @override
  Future<ChartMomentEvent?> getById(String id) async {
    final db = await database.database;
    final row = await ChartMomentEventDao(db).findById(id);

    if (row == null) {
      return null;
    }

    return ChartMomentEventRowMapper.fromRow(row);
  }

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async {
    final db = await database.database;

    final rows = await ChartMomentEventDao(db).findRecent(limit: limit);

    return List.unmodifiable(rows.map(ChartMomentEventRowMapper.fromRow));
  }
}
