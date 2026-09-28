enum ChartViewSize {
  top10(10),
  top25(25),
  top50(50),
  top75(75),
  top100(100),
  top200(200);

  const ChartViewSize(this.limit);

  final int limit;

  static const int officialChartLimit = 100;

  bool get includesOffChartStandings => limit > officialChartLimit;
}
