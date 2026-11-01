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
  const ChartMomentRules({
    this.activatedAtUtc,
    this.catalogStarts = const [],
    this.climbWordingFromUtc,
  });

  /// No activation: every Moment follows the earlier rules.
  static const ChartMomentRules legacy = ChartMomentRules();

  /// The newest refined headline catalog this build carries (SN-50 R-V).
  /// Raise it only together with a new catalog version; a released
  /// version's lines never change.
  static const int currentCatalogVersion = 1;

  final DateTime? activatedAtUtc;

  /// Where catalog versions after the first start on this install. Version
  /// 1 starts at [activatedAtUtc]; each later version at the first run of a
  /// build that carries it (write-once, see MomentRulesActivation).
  final List<RefinedCatalogStart> catalogStarts;

  /// Where stories under the earlier rules start naming how many places a
  /// rising song climbed (SN-50 device polish): the first run of a build
  /// that carries the wording, recorded once. Null keeps every story's
  /// first wording. It changes headlines only, never which Moments are
  /// recorded or told.
  final DateTime? climbWordingFromUtc;

  /// Whether a story that happened at [occurredAt] is told with the climb
  /// wording. Stories from before the start keep the words they were first
  /// published with; a story's own instant is used for every scope, since
  /// none can have been shown before it happened.
  bool statesClimb(DateTime occurredAt) {
    final from = climbWordingFromUtc;
    return from != null && !occurredAt.toUtc().isBefore(from.toUtc());
  }

  /// Whether a Moment of [scope] that happened at [occurredAt], on the
  /// chart week starting at [weekStartUtc], is told under the new rules.
  bool appliesTo({
    required ChartMomentScope scope,
    required DateTime occurredAt,
    required DateTime weekStartUtc,
  }) {
    final activated = activatedAtUtc;
    if (activated == null) return false;

    final at = _boundary(scope, occurredAt, weekStartUtc);
    return !at.toUtc().isBefore(activated.toUtc());
  }

  /// The refined headline catalog version a Moment is told with: the newest
  /// version that had started on this install by the Moment's boundary
  /// (the play for real-time and all-time Moments, the week's start for
  /// weekly ones), so a story keeps the catalog it was first told with.
  /// Null when the Moment follows the earlier rules.
  int? catalogVersionFor({
    required ChartMomentScope scope,
    required DateTime occurredAt,
    required DateTime weekStartUtc,
  }) {
    if (!appliesTo(
      scope: scope,
      occurredAt: occurredAt,
      weekStartUtc: weekStartUtc,
    )) {
      return null;
    }
    final at = _boundary(scope, occurredAt, weekStartUtc).toUtc();
    var version = 1;
    for (final start in catalogStarts) {
      if (start.version > version && !at.isBefore(start.fromUtc.toUtc())) {
        version = start.version;
      }
    }
    return version;
  }

  static DateTime _boundary(
    ChartMomentScope scope,
    DateTime occurredAt,
    DateTime weekStartUtc,
  ) => switch (scope) {
    ChartMomentScope.allTime => occurredAt,
    ChartMomentScope.live || ChartMomentScope.finalized => weekStartUtc,
  };
}

/// Where refined headline catalog [version] starts on this install.
class RefinedCatalogStart {
  const RefinedCatalogStart(this.version, this.fromUtc);

  final int version;
  final DateTime fromUtc;
}
