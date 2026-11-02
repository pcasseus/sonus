import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_movement.dart';
import '../../domain/services/chart_ranking_engine.dart';

/// Which chart a position belongs to: the Sonus Hot 100 (1–100) or Sonus
/// Bubbling Under (101–200). Each moves on its own.
enum ChartZone {
  hot100,
  bubblingUnder;

  static ChartZone? of(int? rank) => rank == null
      ? null
      : rank <= ChartRankingEngine.officialChartLimit
      ? ChartZone.hot100
      : rank <= ChartRankingEngine.extendedStandingsLimit
      ? ChartZone.bubblingUnder
      : null;
}

/// How an entry moved (Charts 2.0 C2).
enum ChartMoveKind {
  up,
  down,
  same,

  /// From Bubbling Under into the Hot 100.
  promoted,

  /// From the Hot 100 down to Bubbling Under.
  demoted,

  /// First-ever appearance.
  debut,

  /// Back after an absence.
  reentry,

  /// No earlier position to compare with.
  unknown,
}

/// The one achievement an entry's badge shows. NEW wins over a
/// simultaneous new peak; RE-ENTRY too.
enum ChartAchievement { none, newEntry, reentry, newPeak }

/// What a chart row shows about movement and achievements.
///
/// Rules:
/// - Movement compares with the previous finalized week on the same chart:
///   the Hot 100 rank for Hot 100 entries, the Top 200 rank for Bubbling
///   Under entries. A recorded debut or re-entry stays one, including a
///   first arrival on the Hot 100 from Bubbling Under; otherwise a move
///   across rank 100 is a promotion or demotion.
/// - Position movement % = positions gained ÷ 99 (the steps on a
///   100-position chart) × 100, kept within −100…+100. It describes rank
///   movement only, never stream growth, and is given only for a move
///   within one chart: none for debuts, re-entries, unknown history or a
///   move between the Hot 100 and Bubbling Under.
/// - New peak: better than the best finalized position before this
///   period. In a finalized week without that fact, a peak reached that
///   week (stored peak = rank, achieved in the week) counts.
/// - NEW and RE-ENTRY are highlighted on a live chart for 24 hours after
///   the entry first appeared there; the facts themselves stay.
/// - On a live chart, achievements are provisional until the week is
///   finalized.
class ChartEntryMovement {
  const ChartEntryMovement._({
    required this.kind,
    required this.positions,
    required this.positionPercent,
    required this.achievement,
    required this.highlighted,
    required this.provisional,
    required this.zone,
  });

  static const highlightWindow = Duration(hours: 24);
  static const chartSteps = 99;

  final ChartMoveKind kind;

  /// Positions gained (positive) or lost (negative); null without a
  /// comparison.
  final int? positions;

  /// −100…+100, only for a move within one chart.
  final double? positionPercent;
  final ChartAchievement achievement;

  /// Whether NEW / RE-ENTRY is still in its 24-hour highlight, or a new
  /// peak is shown; the badge is plain otherwise.
  final bool highlighted;

  /// A live (not yet finalized) chart: achievements are provisional.
  final bool provisional;
  final ChartZone? zone;

  factory ChartEntryMovement.of(
    ChartEntry entry, {
    required bool live,
    required DateTime now,
    DateTime? weekStartUtc,
    DateTime? weekEndUtc,
    int? previousExtendedRank,
  }) {
    final rank = entry.rank;
    final zone = ChartZone.of(rank);
    final hotPrevious =
        entry.previousFinalRank != null &&
            entry.previousFinalRank! <= ChartRankingEngine.officialChartLimit
        ? entry.previousFinalRank
        : null;
    final extended =
        entry.previousExtendedRank ??
        previousExtendedRank ??
        entry.previousFinalRank;
    final previousZone = ChartZone.of(extended);

    ChartMoveKind kind;
    int? positions;
    double? percent;

    final previous = switch (zone) {
      ChartZone.hot100 =>
        hotPrevious ?? (previousZone == ChartZone.hot100 ? extended : null),
      ChartZone.bubblingUnder =>
        previousZone == ChartZone.bubblingUnder ? extended : null,
      null => null,
    };

    if (previous != null) {
      positions = previous - rank;
      percent = (positions / chartSteps * 100).clamp(-100.0, 100.0);
      kind = positions > 0
          ? ChartMoveKind.up
          : positions < 0
          ? ChartMoveKind.down
          : ChartMoveKind.same;
    } else if (extended != null &&
        previousZone != null &&
        zone != null &&
        entry.movement != ChartMovement.newEntry &&
        entry.movement != ChartMovement.reentry) {
      // Between the two charts: real positions, no percentage. A first
      // (or returning) arrival on the Hot 100 from Bubbling Under stays a
      // Hot 100 debut (or re-entry), as recorded.
      positions = extended - rank;
      kind = zone == ChartZone.hot100
          ? ChartMoveKind.promoted
          : ChartMoveKind.demoted;
    } else {
      kind = switch (entry.movement) {
        ChartMovement.newEntry => ChartMoveKind.debut,
        ChartMovement.reentry => ChartMoveKind.reentry,
        _ => ChartMoveKind.unknown,
      };
    }

    final newPeak =
        kind != ChartMoveKind.debut &&
        _isNewPeak(entry, weekStartUtc: weekStartUtc, weekEndUtc: weekEndUtc);

    final achievement = switch (kind) {
      ChartMoveKind.debut => ChartAchievement.newEntry,
      ChartMoveKind.reentry => ChartAchievement.reentry,
      _ => newPeak ? ChartAchievement.newPeak : ChartAchievement.none,
    };

    final appearedAt = zone == ChartZone.hot100
        ? entry.firstHot100At ?? entry.firstChartedAt
        : entry.firstChartedAt;
    final highlighted = switch (achievement) {
      ChartAchievement.newEntry || ChartAchievement.reentry =>
        live &&
            appearedAt != null &&
            now.toUtc().difference(appearedAt.toUtc()) < highlightWindow &&
            !now.toUtc().isBefore(appearedAt.toUtc()),
      ChartAchievement.newPeak => true,
      ChartAchievement.none => false,
    };

    return ChartEntryMovement._(
      kind: kind,
      positions: positions,
      positionPercent: percent,
      achievement: achievement,
      highlighted: highlighted,
      provisional: live,
      zone: zone,
    );
  }

  static bool _isNewPeak(
    ChartEntry entry, {
    DateTime? weekStartUtc,
    DateTime? weekEndUtc,
  }) {
    final prior = entry.priorPeakRank;
    if (prior != null) return entry.rank < prior;
    // A finalized week read from storage: the peak it reached that week.
    if (weekStartUtc == null || weekEndUtc == null) return false;
    final at = entry.peakAchievedAt.toUtc();
    return entry.peakRank == entry.rank &&
        entry.previousFinalRank != null &&
        entry.rank < entry.previousFinalRank! &&
        !at.isBefore(weekStartUtc.toUtc()) &&
        at.isBefore(weekEndUtc.toUtc());
  }

  /// The arrow line: "+4", "−2", "=", "NEW", "RE-ENTRY", or "".
  String get shortLabel => switch (kind) {
    ChartMoveKind.up || ChartMoveKind.promoted => '+${positions!}',
    ChartMoveKind.down || ChartMoveKind.demoted => '−${-positions!}',
    ChartMoveKind.same => '=',
    ChartMoveKind.debut => 'NEW',
    ChartMoveKind.reentry => 'RE-ENTRY',
    ChartMoveKind.unknown => '',
  };

  /// "+4% position" (whole percent, "<1%" for a real move under 0.5%).
  String? get percentLabel {
    final p = positionPercent;
    if (p == null || p == 0) return null;
    final magnitude = p.abs() < 0.5 ? '<1' : '${p.abs().round()}';
    return '${p > 0 ? '+' : '−'}$magnitude% position';
  }

  /// "from Bubbling Under" / "to Bubbling Under" for cross-chart moves.
  String? get crossChartNote => switch (kind) {
    ChartMoveKind.promoted => 'from Bubbling Under',
    ChartMoveKind.demoted => 'to Bubbling Under',
    _ => null,
  };

  /// What a screen reader hears.
  String spokenLabel(int rank) {
    final n = positions?.abs() ?? 0;
    final places = n == 1 ? 'place' : 'places';
    final move = switch (kind) {
      ChartMoveKind.up => 'Up $n $places',
      ChartMoveKind.down => 'Down $n $places',
      ChartMoveKind.same => 'No change',
      ChartMoveKind.promoted => 'Up $n $places from Bubbling Under',
      ChartMoveKind.demoted => 'Down $n $places to Bubbling Under',
      ChartMoveKind.debut => rank == 1 ? 'New entry at number 1' : 'New entry',
      ChartMoveKind.reentry => 'Re-entry',
      ChartMoveKind.unknown => 'No earlier position',
    };
    final p = positionPercent;
    final percent = p == null || p == 0
        ? ''
        : ', ${p.abs() < 0.5 ? 'under 1' : p.abs().round()} percent position '
              'movement';
    final peak = achievement == ChartAchievement.newPeak
        ? (provisional ? ', provisional new peak' : ', new peak')
        : '';
    return '$move$percent$peak';
  }
}
