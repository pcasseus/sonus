class MonthlyDurationChange {
  const MonthlyDurationChange({required this.current, required this.previous});

  final Duration current;
  final Duration previous;

  Duration get absoluteChange {
    return Duration(
      milliseconds: current.inMilliseconds - previous.inMilliseconds,
    );
  }

  double? get percentChange {
    final previousMilliseconds = previous.inMilliseconds;

    if (previousMilliseconds == 0) {
      return current == Duration.zero ? 0 : null;
    }

    return absoluteChange.inMilliseconds / previousMilliseconds;
  }

  bool get increased => absoluteChange > Duration.zero;

  bool get decreased => absoluteChange < Duration.zero;

  bool get unchanged => absoluteChange == Duration.zero;
}
