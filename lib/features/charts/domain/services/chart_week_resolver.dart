import '../models/chart_week.dart';

class ChartWeekResolver {
  const ChartWeekResolver();

  ChartWeek resolve(DateTime referenceLocal) {
    final startOfDay = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day,
    );

    final daysSinceSunday = startOfDay.weekday % 7;

    final startLocal = DateTime(
      startOfDay.year,
      startOfDay.month,
      startOfDay.day - daysSinceSunday,
    );

    final endLocal = DateTime(
      startLocal.year,
      startLocal.month,
      startLocal.day + 7,
    );

    return ChartWeek(startUtc: startLocal.toUtc(), endUtc: endLocal.toUtc());
  }
}
