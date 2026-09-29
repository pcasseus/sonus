class ChartMomentLongevityState {
  const ChartMomentLongevityState({
    required this.totalChartWeeks,
    required this.consecutiveChartWeeks,
    required this.totalThresholdWeeks,
    required this.consecutiveThresholdWeeks,
  });

  final int totalChartWeeks;
  final int consecutiveChartWeeks;

  final Map<int, int> totalThresholdWeeks;
  final Map<int, int> consecutiveThresholdWeeks;

  int totalWeeksAt(int threshold) => totalThresholdWeeks[threshold] ?? 0;

  int consecutiveWeeksAt(int threshold) =>
      consecutiveThresholdWeeks[threshold] ?? 0;
}
