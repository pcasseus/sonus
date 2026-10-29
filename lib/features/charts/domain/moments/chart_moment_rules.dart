/// When the SN-50 Moments rules start (guaranteed entries, first
/// thresholds, verified rivals, distinct stories from one play).
///
/// Moments that happened earlier keep the stories they were published
/// with: old weeks and plays are never re-told or backfilled under the new
/// rules, and their stored events keep their keys.
abstract final class ChartMomentRules {
  static final DateTime refinedFromUtc = DateTime.utc(2026, 11, 1);

  static bool isRefined(DateTime occurredAt) =>
      !occurredAt.toUtc().isBefore(refinedFromUtc);
}
