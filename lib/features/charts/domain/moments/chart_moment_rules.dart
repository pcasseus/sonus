import 'chart_moment_scope.dart';

/// When the SN-50 Moments rules apply (guaranteed entries, first
/// thresholds, verified rivals, distinct stories from one play).
///
/// They start at [activatedAtUtc], the instant an approved build first ran
/// (SN-50 R2), and never earlier: Moments from before it keep the stories
/// they were published with, nothing is re-told or backfilled, and stored
/// events keep their keys. Without an activation every Moment follows the
/// earlier rules.
///
/// Real-time and all-time Moments follow the new rules from the activation
/// instant on. Weekly Moments follow them only for chart weeks that start
/// at or after it, so the week running at activation keeps the earlier
/// rules. Both compare UTC instants, whatever the device time zone.
class ChartMomentRules {
  const ChartMomentRules({this.activatedAtUtc});

  /// No activation: every Moment follows the earlier rules.
  static const ChartMomentRules legacy = ChartMomentRules();

  final DateTime? activatedAtUtc;

  /// Whether a Moment of [scope] that happened at [occurredAt], on the
  /// chart week starting at [weekStartUtc], is told under the new rules.
  bool appliesTo({
    required ChartMomentScope scope,
    required DateTime occurredAt,
    required DateTime weekStartUtc,
  }) {
    final activated = activatedAtUtc;
    if (activated == null) return false;

    final at = switch (scope) {
      ChartMomentScope.allTime => occurredAt,
      ChartMomentScope.live || ChartMomentScope.finalized => weekStartUtc,
    };
    return !at.toUtc().isBefore(activated.toUtc());
  }
}
