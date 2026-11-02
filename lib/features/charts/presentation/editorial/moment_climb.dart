import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
import 'moment_publisher.dart';

/// How many places a rising song climbed, when the story can say so
/// truthfully (SN-50 device polish).
///
/// Only a real, comparable move counts: the song had a rank before this
/// Moment on the same chart, and now ranks higher. Debuts and re-entries
/// have no comparable rank, and a move between Bubbling Under and the Hot
/// 100 is a change of chart, not a climb, so none of them has one.
abstract final class MomentClimb {
  /// Stories whose headline names the climb, from the climb wording's
  /// start on (ChartMomentRules.statesClimb).
  static const Set<MomentFamily> headlineFamilies = {
    MomentFamily.songBigClimb,
    MomentFamily.songBiggestGainer,
    MomentFamily.songNewPeak,
    MomentFamily.songPeakMatch,
    MomentFamily.songFirstNumberOne,
    MomentFamily.songReturnsToNumberOne,
    MomentFamily.releaseClimb,
  };

  /// Stories that show the climb beside the headline (every story, old or
  /// new, without changing its words).
  static const Set<MomentFamily> families = {
    ...headlineFamilies,
    MomentFamily.songHot100MajorJump,
    MomentFamily.artistFirstTop10,
    MomentFamily.artistNthTop10,
    MomentFamily.artistFirstNumberOne,
    MomentFamily.artistNthNumberOne,
  };

  /// Places climbed in [item], told as [family]; null without a
  /// comparable rise.
  static int? of(
    ChartMomentFeedItem item,
    MomentFamily family,
    MomentFacts facts,
  ) {
    if (!families.contains(family)) return null;
    for (final event in item.events) {
      if (event.eventType == ChartMomentEventType.debut ||
          event.eventType == ChartMomentEventType.reentry) {
        return null;
      }
    }
    final before = facts.previousRank;
    final now = facts.rank;
    if (before == null || now == null || now >= before) return null;
    // Albums & EPs is one chart; songs move between two.
    const limit = ChartRankingEngine.officialChartLimit;
    if (facts.chartType == ChartType.songs &&
        (before > limit) != (now > limit)) {
      return null;
    }
    return before - now;
  }

  /// "1 place", "12 places".
  static String placesText(int places) =>
      places == 1 ? '1 place' : '$places places';
}

/// Headlines that name the climb, in both publishers' voices, for stories
/// under the earlier rules from the climb wording's start on. The published
/// catalog (MomentHeadlines.legacyOf) is never edited: stories told before
/// the start keep its words.
abstract final class ClimbHeadlines {
  static List<HeadlineVariant> of(MomentFamily family) =>
      _lines[family] ?? const [];

  static const _d = MomentPublisher.sonusDaily;
  static const _p = MomentPublisher.pulsePop;
  static const _climb = {MomentFact.rank, MomentFact.places};

  static String _n(MomentFacts f) => MomentClimb.placesText(f.places!);

  static final Map<MomentFamily, List<HeadlineVariant>> _lines = {
    MomentFamily.songBigClimb: [
      HeadlineVariant(
        'climb-big-d1',
        _d,
        (f) => '${f.subject} climbs ${_n(f)} to #${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-big-d2',
        _d,
        (f) => '${f.subject} rises ${_n(f)} to #${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-big-p1',
        _p,
        (f) => 'Up ${_n(f)}! ${f.subject} jumps to #${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-big-p2',
        _p,
        (f) =>
            '${f.artist} on the move: ${f.work} climbs ${_n(f)} to '
            '#${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.songBiggestGainer: [
      HeadlineVariant(
        'climb-gainer-d1',
        _d,
        (f) =>
            "${f.subject} makes the week's biggest climb, up ${_n(f)} to "
            '#${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-gainer-p1',
        _p,
        (f) =>
            "The week's biggest gainer: ${f.subject} rises ${_n(f)} to "
            '#${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.songNewPeak: [
      HeadlineVariant(
        'climb-peak-d1',
        _d,
        (f) =>
            '${f.subject} climbs ${_n(f)} to a new peak of #${f.rank} on '
            '${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-peak-p1',
        _p,
        (f) =>
            'New peak! ${f.subject} rises ${_n(f)} to #${f.rank} on '
            '${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.songPeakMatch: [
      HeadlineVariant(
        'climb-match-d1',
        _d,
        (f) =>
            '${f.subject} climbs ${_n(f)} to #${f.rank}, matching its peak '
            'on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-match-p1',
        _p,
        (f) =>
            '${f.subject} rises ${_n(f)} back to its #${f.rank} peak on '
            '${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.songFirstNumberOne: [
      HeadlineVariant(
        'climb-first1-d1',
        _d,
        (f) =>
            '${f.subject} climbs ${_n(f)} to reach #1 on ${f.chart} for the '
            'first time.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-first1-p1',
        _p,
        (f) => 'Top spot! ${f.subject} rises ${_n(f)} to #1 on ${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.releaseClimb: [
      HeadlineVariant(
        'climb-release-d1',
        _d,
        (f) =>
            '${f.work} by ${f.artist} climbs ${_n(f)} to #${f.rank} on '
            '${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-release-d2',
        _d,
        (f) =>
            "${MomentFacts.possessive(f.artist)} ${f.releaseWord} ${f.title} "
            'rises ${_n(f)} to #${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-release-p1',
        _p,
        (f) =>
            'Moving up: ${f.work} by ${f.artist} gains ${_n(f)}, now #${f.rank} '
            'on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-release-p2',
        _p,
        (f) =>
            '${f.artist} on the rise: ${f.work} climbs ${_n(f)} to '
            '#${f.rank} on ${f.chart}.',
        requires: _climb,
      ),
    ],
    MomentFamily.songReturnsToNumberOne: [
      HeadlineVariant(
        'climb-return1-d1',
        _d,
        (f) => '${f.subject} climbs ${_n(f)} back to #1 on ${f.chart}.',
        requires: _climb,
      ),
      HeadlineVariant(
        'climb-return1-p1',
        _p,
        (f) =>
            'Back on top! ${f.subject} rises ${_n(f)} to return to #1 on '
            '${f.chart}.',
        requires: _climb,
      ),
    ],
  };
}
