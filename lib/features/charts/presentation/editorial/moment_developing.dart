import '../../application/services/chart_moment_feed_pager.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_rules.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_climb.dart';

/// One step of a developing story: a recorded climb, as the update thread
/// tells it.
class MomentStoryUpdate {
  const MomentStoryUpdate({
    required this.eventId,
    required this.occurredAt,
    required this.text,
    required this.rank,
    required this.previousRank,
  });

  /// The recorded event it tells (its stored identity).
  final String eventId;
  final DateTime occurredAt;
  final String text;
  final int rank;
  final int previousRank;
}

/// Developing stories (SN-50 complete coverage): a song or release that
/// climbs the Career chart again and again within one local day gets one
/// living story, updated with each climb, instead of a post per play.
///
/// Built only from recorded events, deterministically, so it survives
/// restarts and refreshes and can never duplicate: the same events always
/// make the same story with the same thread. A day is the unit because the
/// feed loads whole days; once a day is over its stories no longer change.
///
/// A chain is one entity on one chart (the Hot 100 and Bubbling Under are
/// separate; a move between them is an arrival, told on its own), climbs
/// only, from the device-polish start, outside the refined rules.
abstract final class DevelopingStories {
  /// The chain [event] belongs to, or null when it is not a climb a
  /// developing story tells.
  static String? keyOf(ChartMomentEvent event, ChartMomentRules rules) {
    if (event.scope != ChartMomentScope.allTime ||
        event.eventType != ChartMomentEventType.rankRise) {
      return null;
    }
    final before = event.previousRank;
    final now = event.currentRank;
    if (before == null || now == null || now >= before) return null;
    if (!rules.tellsEveryChartEvent(event.occurredAt)) return null;
    if (rules.appliesTo(
      scope: event.scope,
      occurredAt: event.occurredAt,
      weekStartUtc: event.weekStartUtc,
    )) {
      return null;
    }
    const limit = ChartRankingEngine.officialChartLimit;
    final String zone;
    if (event.chartType == ChartType.songs) {
      if ((before > limit) != (now > limit)) return null;
      zone = now > limit ? 'bubbling' : 'hot100';
    } else {
      zone = 'chart';
    }
    return '${event.chartType.name}|$zone|${event.entity.entityId}|'
        '${ChartMomentFeedPager.localDay(event.occurredAt)}';
  }

  /// Every chain in [events], each oldest first.
  static Map<String, List<ChartMomentEvent>> chains(
    Iterable<ChartMomentEvent> events,
    ChartMomentRules rules,
  ) {
    final chains = <String, List<ChartMomentEvent>>{};
    final seen = <String>{};
    for (final event in events) {
      final key = keyOf(event, rules);
      if (key == null || !seen.add(event.deduplicationKey)) continue;
      chains.putIfAbsent(key, () => []).add(event);
    }
    for (final chain in chains.values) {
      chain.sort((a, b) {
        final byTime = a.occurredAt.toUtc().compareTo(b.occurredAt.toUtc());
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    }
    return chains;
  }

  /// The thread, oldest first: each climb as it happened. A later climb
  /// that starts lower than the one before ended slipped in between, and
  /// says so; movement is never added up across a slip.
  static List<MomentStoryUpdate> thread(
    List<ChartMomentEvent> chain, {
    required String title,
    required String chart,
    String? subject,
  }) {
    final updates = <MomentStoryUpdate>[];
    int? lastRank;
    for (final event in chain) {
      final before = event.previousRank!;
      final now = event.currentRank!;
      final places = MomentClimb.placesText(before - now);
      final newHigh =
          event.previousPeakRank != null && now < event.previousPeakRank!;
      final end = newHigh ? ', a new career high.' : '.';
      final String text;
      if (lastRank == null) {
        // The first line names the song with its credits.
        text = '${subject ?? title} climbs $places to #$now on $chart$end';
      } else if (before == lastRank) {
        text = 'UPDATE: $title climbs another $places to #$now$end';
      } else if (before > lastRank) {
        text =
            'UPDATE: After slipping to #$before, $title rebounds $places '
            'to #$now$end';
      } else {
        text = 'UPDATE: $title climbs $places to #$now$end';
      }
      updates.add(
        MomentStoryUpdate(
          eventId: event.id,
          occurredAt: event.occurredAt,
          text: text,
          rank: now,
          previousRank: before,
        ),
      );
      lastRank = now;
    }
    return updates;
  }
}

/// What a developing story says about its whole chain.
class DevelopingSummary {
  DevelopingSummary(List<ChartMomentEvent> chain)
    : start = chain.first.previousRank!,
      current = chain.last.currentRank!,
      best = chain
          .map((event) => event.currentRank!)
          .reduce((a, b) => a < b ? a : b),
      latestFrom = chain.last.previousRank!,
      previousEnd = chain.length > 1
          ? chain[chain.length - 2].currentRank
          : null,
      newHigh =
          chain.last.previousPeakRank != null &&
          chain.last.currentRank! < chain.last.previousPeakRank!;

  /// Where the story began: the position before its first climb.
  final int start;

  /// The latest position.
  final int current;

  /// The best position reached during the story.
  final int best;

  /// Where the latest climb started.
  final int latestFrom;

  /// Where the climb before the latest one ended.
  final int? previousEnd;

  /// The latest position is the best the entity has ever held.
  final bool newHigh;

  /// Places gained since the story began (can be zero or less after a slip).
  int get net => start - current;

  /// Places gained by the latest climb alone.
  int get latest => latestFrom - current;

  /// The latest climb started below where the one before ended.
  bool get reboundedAfterSlip =>
      previousEnd != null && latestFrom > previousEnd!;
}
