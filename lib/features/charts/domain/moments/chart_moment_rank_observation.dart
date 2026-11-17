class ChartMomentRankObservation {
  const ChartMomentRankObservation({
    required this.sourceEventId,
    required this.entityId,
    required this.hadPreviousObservation,
    required this.previousRank,
    required this.currentRank,
    this.previousPeakRank,
    this.currentPeakRank,
    this.previousFinalizedRank,
    this.chartedEarlierThisWeek = false,
    required this.observedAt,
  });

  /// Stable id of the qualified play/event that caused this standings
  /// recalculation. It allows replaying a chart build without duplicating
  /// Moments already persisted from the same underlying listening event.
  final String sourceEventId;

  final String entityId;

  /// Distinguishes a true first reconstruction observation from an entity
  /// that was already observed outside the visible Top 200.
  final bool hadPreviousObservation;

  /// Previous visible Top-200 rank.
  ///
  /// Null means the entity was outside the Top 200, unless
  /// [hadPreviousObservation] is false, in which case there is no prior
  /// observation at all.
  final int? previousRank;

  /// Current visible Top-200 rank.
  ///
  /// Null means the entity currently sits outside the Top 200.
  final int? currentRank;

  /// Best visible Top-200 rank reached before this observation, combining
  /// finalized history and earlier live observations in this reconstruction.
  ///
  /// Null means the entity had never previously reached the Top 200.
  final int? previousPeakRank;

  /// Best visible Top-200 rank reached through this observation.
  ///
  /// Null means the entity still has never reached the Top 200.
  final int? currentPeakRank;

  /// Rank in the immediately preceding finalized week within the persisted
  /// Top 200. Null means the entity did not finish that week in the Top 200.
  final int? previousFinalizedRank;

  /// Whether the entity already held a Top-200 position earlier in this
  /// week's reconstruction. A return after such a dip is provisional churn
  /// within the live week, never a debut or re-entry: those come from
  /// finalized chart history only (user decision 2026-11-16).
  final bool chartedEarlierThisWeek;

  final DateTime observedAt;

  bool get isFirstObservation => !hadPreviousObservation;

  bool get wasCharting => previousRank != null;

  bool get isCharting => currentRank != null;

  bool get enteredChart =>
      hadPreviousObservation && previousRank == null && currentRank != null;

  bool get exitedChart =>
      hadPreviousObservation && previousRank != null && currentRank == null;

  bool get changed => hadPreviousObservation && previousRank != currentRank;

  bool get rose =>
      previousRank != null &&
      currentRank != null &&
      currentRank! < previousRank!;

  bool get fell =>
      previousRank != null &&
      currentRank != null &&
      currentRank! > previousRank!;
}
