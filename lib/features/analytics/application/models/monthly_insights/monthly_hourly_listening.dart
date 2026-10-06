class MonthlyHourlyListening {
  const MonthlyHourlyListening({
    required this.hour,
    required this.streams,
    required this.listeningDuration,
  });

  final int hour;
  final int streams;
  final Duration listeningDuration;
}
