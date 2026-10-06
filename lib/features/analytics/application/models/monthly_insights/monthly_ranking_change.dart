class MonthlyRankingChange {
  const MonthlyRankingChange({
    required this.currentValue,
    required this.previousValue,
  });

  final int currentValue;
  final int previousValue;

  int get absoluteChange => currentValue - previousValue;

  double? get percentChange {
    if (previousValue == 0) {
      return currentValue == 0 ? 0 : null;
    }

    return absoluteChange / previousValue;
  }

  bool get isNew => currentValue > 0 && previousValue == 0;

  bool get increased => absoluteChange > 0;

  bool get decreased => absoluteChange < 0;

  bool get unchanged => absoluteChange == 0;
}
