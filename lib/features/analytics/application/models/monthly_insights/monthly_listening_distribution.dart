import 'monthly_daily_listening.dart';
import 'monthly_hourly_listening.dart';

class MonthlyListeningDistribution {
  const MonthlyListeningDistribution({required this.days, required this.hours});

  final List<MonthlyDailyListening> days;
  final List<MonthlyHourlyListening> hours;

  MonthlyDailyListening? get busiestDay {
    MonthlyDailyListening? result;

    for (final day in days) {
      final current = result;

      if (current == null ||
          day.streams > current.streams ||
          (day.streams == current.streams &&
              day.localDate.isBefore(current.localDate))) {
        result = day;
      }
    }

    return result;
  }

  MonthlyHourlyListening? get mostActiveHour {
    MonthlyHourlyListening? result;

    for (final hour in hours) {
      final current = result;

      if (current == null ||
          hour.listeningDuration > current.listeningDuration ||
          (hour.listeningDuration == current.listeningDuration &&
              hour.streams > current.streams)) {
        result = hour;
      }
    }

    return result;
  }
}
