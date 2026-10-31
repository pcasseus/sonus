/// The verified facts of a chart jump, from finalized weeks only. Places
/// and streams are separate facts: a place gained is never a stream.
class ChartJumpFacts {
  const ChartJumpFacts({
    required this.fromRank,
    required this.toRank,
    required this.weeks,
    this.weekStreams,
    this.previousWeekStreams,
  });

  /// The rank before the first climbing week.
  final int fromRank;

  /// This week's rank.
  final int toRank;

  /// Consecutive climbing weeks, this one included.
  final int weeks;

  int get placesGained => fromRank - toRank;

  /// Qualified streams in this finalized week.
  final int? weekStreams;

  /// Qualified streams in the week before, only when that week's entry was
  /// verified as this song's previous rank.
  final int? previousWeekStreams;

  /// More (or fewer) qualified streams than the week before; null unless
  /// both weeks are known.
  int? get streamGain {
    final now = weekStreams;
    final before = previousWeekStreams;
    return now == null || before == null ? null : now - before;
  }
}
