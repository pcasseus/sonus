import '../models/analytics_period.dart';
import '../models/analytics_time_window.dart';

class AnalyticsTimeWindowResolver {
  const AnalyticsTimeWindowResolver();

  AnalyticsTimeWindow resolve({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
  }) {
    switch (period) {
      case AnalyticsPeriod.day:
        return _day(referenceLocal);

      case AnalyticsPeriod.week:
        return _week(referenceLocal);

      case AnalyticsPeriod.month:
        return _month(referenceLocal);

      case AnalyticsPeriod.year:
        return _year(referenceLocal);

      case AnalyticsPeriod.lifetime:
        return const AnalyticsTimeWindow(startUtc: null, endUtc: null);
    }
  }

  AnalyticsTimeWindow _day(DateTime referenceLocal) {
    final startLocal = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day,
    );

    final endLocal = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day + 1,
    );

    return _fromLocalBounds(startLocal, endLocal);
  }

  AnalyticsTimeWindow _week(DateTime referenceLocal) {
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

    return _fromLocalBounds(startLocal, endLocal);
  }

  AnalyticsTimeWindow _month(DateTime referenceLocal) {
    final startLocal = DateTime(referenceLocal.year, referenceLocal.month);

    final endLocal = DateTime(referenceLocal.year, referenceLocal.month + 1);

    return _fromLocalBounds(startLocal, endLocal);
  }

  AnalyticsTimeWindow _year(DateTime referenceLocal) {
    final startLocal = DateTime(referenceLocal.year);

    final endLocal = DateTime(referenceLocal.year + 1);

    return _fromLocalBounds(startLocal, endLocal);
  }

  AnalyticsTimeWindow _fromLocalBounds(DateTime startLocal, DateTime endLocal) {
    return AnalyticsTimeWindow(
      startUtc: startLocal.toUtc(),
      endUtc: endLocal.toUtc(),
    );
  }
}
