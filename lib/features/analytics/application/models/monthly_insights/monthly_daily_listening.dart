class MonthlyDailyListening {
  const MonthlyDailyListening({
    required this.localDate,
    required this.streams,
    required this.listeningDuration,
  });

  final DateTime localDate;
  final int streams;
  final Duration listeningDuration;
}
