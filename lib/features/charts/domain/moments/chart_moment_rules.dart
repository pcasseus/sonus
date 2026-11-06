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
    this.devicePolishFromUtc,
    this.chronicleFromUtc,
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

  /// Where the SN-50 device polish starts for stories under the earlier
  /// rules: the first run of a build that carries it, recorded once. From
  /// then on a rising song's headline names the places it climbed
  /// ([statesClimb]) and every recorded chart achievement is told, with no
  /// daily cap ([tellsEveryChartEvent]). Null keeps every story as first
  /// published. It changes which recorded Moments are told and how, never
  /// which are recorded.
  final DateTime? devicePolishFromUtc;

  /// Where the App Update 1.1 Moments chronicle starts on this install:
  /// the first run of a build that carries it, recorded once (like
  /// [devicePolishFromUtc], on every build). From then on the all-time
  /// charts also record zone returns, Hot 100 and Top 200 exits, Hot 100
  /// returns and daily #1 holds, and a play's climb, new peak and new zones
  /// are told as one chart-move story. Stories from before it keep what
  /// they were first published as: nothing is re-told or backfilled.
  final DateTime? chronicleFromUtc;

  /// Whether a story that happened at [occurredAt] is told by the
  /// chronicle (App Update 1.1).
  bool chronicles(DateTime occurredAt) {
    final from = chronicleFromUtc;
    return from != null && !occurredAt.toUtc().isBefore(from.toUtc());
  }

  /// These rules with the chronicle starting at [fromUtc].
  ChartMomentRules withChronicle(DateTime? fromUtc) =>
      fromUtc == chronicleFromUtc
      ? this
      : ChartMomentRules(
          activatedAtUtc: activatedAtUtc,
          catalogStarts: catalogStarts,
          devicePolishFromUtc: devicePolishFromUtc,
          chronicleFromUtc: fromUtc,
        );

  /// Whether a story that happened at [occurredAt] follows the device
  /// polish. Stories from before the start keep what they were first
  /// published as, so nothing is re-told or backfilled; a story's own
  /// instant is used for every scope, since none can have been shown before
  /// it happened.
  bool _polished(DateTime occurredAt) {
    final from = devicePolishFromUtc;
    return from != null && !occurredAt.toUtc().isBefore(from.toUtc());
  }

  /// Whether a rising song's headline names the places it climbed.
  bool statesClimb(DateTime occurredAt) => _polished(occurredAt);

  /// Whether every recorded chart achievement is told: every debut,
  /// re-entry, new peak and climb on the weekly charts as well as the
  /// permanent one, and no daily cap on smaller stories.
  bool tellsEveryChartEvent(DateTime occurredAt) => _polished(occurredAt);

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
