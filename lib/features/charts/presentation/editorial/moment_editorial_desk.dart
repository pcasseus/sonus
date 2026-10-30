import '../../application/models/chart_moment_feed_item.dart';
import '../../application/services/chart_moment_feed_pager.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_rules.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../domain/services/chart_ranking_engine.dart';
import 'moment_publisher.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
import 'moment_story_planner.dart';
import 'moment_visuals.dart';

/// One published story: who wrote it, what it says, and what it shows.
class MomentStory {
  const MomentStory({
    required this.item,
    required this.family,
    required this.facts,
    required this.publisher,
    required this.variantId,
    required this.headline,
    required this.kicker,
    required this.status,
    required this.visual,
    this.body,
    this.rank,
  });

  final ChartMomentFeedItem item;
  final MomentFamily family;
  final MomentFacts facts;
  final MomentPublisher publisher;

  /// Which headline of the family was used.
  final String variantId;
  final String headline;

  /// A second paragraph, only when it adds a verified fact.
  final String? body;

  /// For example "SONUS HOT 100" or "SONUS BUBBLING UNDER": the card's
  /// only mention of the chart (SN-50 F-Q22).
  final String kicker;

  /// The achievement badge, for example "NUMBER ONE".
  final String status;

  /// The chart position badge. Stories about an artist show none, except
  /// the artist's own #1 among your artists (F-Q23).
  final int? rank;
  final MomentVisual visual;

  String get id => item.id;
  DateTime get occurredAt => item.occurredAt;
}

/// The Sonus Moments editorial desk (SN-45).
///
/// From recorded chart facts it decides which stories to publish, which
/// publisher writes each one, and which of the family's headlines it uses:
///
/// - **Stable:** a story's publisher and headline depend only on its own
///   recorded identity and the stories published before it, so reopening
///   the feed, restarting the app or syncing never rewrites a story.
/// - **Varied:** a story never repeats the headline of the story just
///   before it when the family has another that fits.
/// - **Truthful:** a headline is only used when the story has every fact
///   it states; otherwise another one, or the family's plain one, is used.
/// - **Not spam:** minor stories (deep debuts, Bubbling Under arrivals) are
///   limited to [minorStoriesPerDay] a day; the first ones of the day are
///   kept, so later plays never remove a story already shown. Under the
///   SN-50 rules ([MomentStoryPlanner]) chart entries are guaranteed and
///   never count toward that cap.
class MomentEditorialDesk {
  const MomentEditorialDesk({
    required this.lookups,
    this.rules = ChartMomentRules.legacy,
    this.minorStoriesPerDay = 3,
  });

  final MomentLookups lookups;

  /// Which stories follow the SN-50 rules; none without an activation.
  final ChartMomentRules rules;
  final int minorStoriesPerDay;

  /// The weekly chart's largest climb worth a story.
  static const int biggestGainerMinimumPlaces = 10;

  /// Published stories, newest first.
  List<MomentStory> compose(Iterable<ChartMomentFeedItem> items) {
    final chronological = items.toList()
      ..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final gainers = _biggestGainers(chronological, rules);
    final planner = MomentStoryPlanner(chronological, biggestGainers: gainers);

    final minorPerDay = <String, int>{};
    final stories = <MomentStory>[];
    String? previousVariant;

    for (final item in chronological) {
      final refined = rules.appliesTo(
        scope: item.scope,
        occurredAt: item.occurredAt,
        weekStartUtc: item.weekStartUtc,
      );
      final planned = refined ? planner.plan(item) : _legacyPlan(item, gainers);

      for (final moment in planned) {
        final facts = MomentFacts.of(moment.item, lookups, refined: refined);
        if (!moment.mandatory &&
            moment.family.tierFor(facts.rank) == MomentTier.minor) {
          // The feed is paged in these same days.
          final day = ChartMomentFeedPager.localDay(item.occurredAt);
          final count = minorPerDay[day] ?? 0;
          if (count >= minorStoriesPerDay) continue;
          minorPerDay[day] = count + 1;
        }

        final story = _write(
          moment.item,
          moment.family,
          facts,
          previousVariant,
          excluded: moment.excludedVariants,
        );
        previousVariant = story.variantId;
        stories.add(story);
      }
    }

    return List.unmodifiable(stories.reversed);
  }

  /// Before the SN-50 rules: one story per group, as first published.
  static List<PlannedMoment> _legacyPlan(
    ChartMomentFeedItem item,
    Set<String> gainers,
  ) {
    final family = MomentFamily.of(
      item,
      biggestGainer: gainers.contains(item.id),
    );
    return family == null ? const [] : [PlannedMoment(item, family)];
  }

  MomentStory _write(
    ChartMomentFeedItem item,
    MomentFamily family,
    MomentFacts facts,
    String? previousVariant, {
    Set<String> excluded = const {},
  }) {
    final variants = [
      for (final variant in MomentHeadlines.of(family))
        if (!excluded.contains(variant.id)) variant,
    ];
    final publisher = facts.refined
        ? publisherFor(family)
        : _hash('${item.id}|publisher').isEven
        ? MomentPublisher.sonusDaily
        : MomentPublisher.pulsePop;

    var candidates = [
      for (final variant in variants)
        if (variant.publisher == publisher && variant.fits(facts)) variant,
    ];
    // A verified displacement is the story: say who was passed.
    if (facts.rivalTitle != null) {
      final naming = [
        for (final variant in candidates)
          if (variant.requires.contains(MomentFact.rival)) variant,
      ];
      if (naming.isNotEmpty) candidates = naming;
    }
    if (candidates.isEmpty) {
      candidates = [
        for (final variant in variants)
          if (variant.fits(facts)) variant,
      ];
    }
    // Plain wording when no headline's facts are all there.
    if (candidates.isEmpty) {
      candidates = [
        HeadlineVariant(
          'neutral-${family.name}',
          publisher,
          (f) => _neutralHeadline(family, f),
        ),
      ];
    }

    var index = _hash('${item.id}|headline') % candidates.length;
    if (candidates[index].id == previousVariant && candidates.length > 1) {
      index = (index + 1) % candidates.length;
    }
    final variant = candidates[index];
    final headline = variant.build(facts);

    return MomentStory(
      item: item,
      family: family,
      facts: facts,
      publisher: variant.publisher,
      variantId: variant.id,
      headline: headline,
      body: _supportingText(family, facts, variant),
      kicker: _kicker(family, facts),
      status: _status(family),
      rank: switch (family) {
        MomentFamily.artistTopArtist => 1,
        MomentFamily.artistSimultaneous ||
        MomentFamily.artistSimultaneousReleases ||
        MomentFamily.artistStreamMilestone => null,
        _ => facts.rank,
      },
      visual: MomentVisuals.select(
        item: item,
        family: family,
        facts: facts,
        variant: variant,
        lookups: lookups,
        headline: headline,
      ),
    );
  }

  static String _neutralHeadline(MomentFamily family, MomentFacts facts) {
    if (family.isNumberOne) return '${facts.work} is #1 on ${facts.chart}.';
    final rank = facts.rank;
    if (rank != null) return '${facts.subject} is #$rank on ${facts.chart}.';
    return '${facts.subject} has news on Sonus.';
  }

  /// At most two sentences of verified facts the headline did not state.
  static String? _supportingText(
    MomentFamily family,
    MomentFacts facts,
    HeadlineVariant variant,
  ) {
    final used = variant.requires;
    final it = facts.chartType == ChartType.songs
        ? 'The song'
        : 'The ${facts.releaseWord}';
    final sentences = <String>[];

    final newTop = facts.newTopArtist;
    final passed = facts.passedTopArtist;
    if (newTop != null && passed != null) {
      sentences.add(
        'The same stream makes $newTop your #1 artist, passing $passed.',
      );
    }

    if (family.isNumberOne &&
        facts.rivalTitle != null &&
        !used.contains(MomentFact.rival)) {
      sentences.add('${facts.rivalSubject} had been #1.');
    }

    final climbs = switch (family) {
      MomentFamily.songFirstNumberOne ||
      MomentFamily.songReturnsToNumberOne ||
      MomentFamily.songNewPeak ||
      MomentFamily.songHot100Breakthrough ||
      MomentFamily.releaseReachesNumberOne ||
      MomentFamily.releaseReturnsToNumberOne ||
      MomentFamily.releaseNewPeak ||
      MomentFamily.artistFirstNumberOne ||
      MomentFamily.artistNthNumberOne ||
      MomentFamily.artistFirstTop10 ||
      MomentFamily.artistNthTop10 => true,
      _ => false,
    };
    final previous = facts.previousRank;
    final peak = facts.previousPeak;
    final peakNamed =
        used.contains(MomentFact.previousPeak) && previous == peak;
    final tellsPeak =
        (family == MomentFamily.songReentry ||
            family == MomentFamily.releaseReentry ||
            family == MomentFamily.songNewPeak ||
            family == MomentFamily.releaseNewPeak) &&
        peak != null &&
        !used.contains(MomentFact.previousPeak);
    // SN-50: no single stream moved a finished week (F-Q8/F-Q24).
    if (climbs &&
        !(facts.weekly && facts.refined) &&
        previous != null &&
        previous != facts.rank &&
        !peakNamed &&
        !used.contains(MomentFact.previousRank)) {
      // One sentence when the rank before this stream was also the best.
      sentences.add(
        tellsPeak && previous == peak
            ? '$it was at #$previous, its best so far, before this stream.'
            : '$it was at #$previous before this stream.',
      );
    }

    if (tellsPeak && !(climbs && previous == peak && previous != null)) {
      sentences.add('Its previous best was #$peak.');
    }

    final owner = facts.ownerName;
    if (owner != null &&
        facts.chartType == ChartType.songs &&
        !used.contains(MomentFact.owner)) {
      sentences.add('${facts.work} belongs to $owner.');
    }

    final streams = facts.streams;
    final milestoneStory = switch (family) {
      MomentFamily.songStreamMilestone ||
      MomentFamily.releaseStreamMilestone ||
      MomentFamily.artistStreamMilestone => true,
      _ => false,
    };
    // A handful of streams is what every early story has; it is not worth
    // a sentence.
    if (streams != null &&
        facts.hasNotableStreams &&
        !milestoneStory &&
        !used.contains(MomentFact.streams)) {
      sentences.add(
        family == MomentFamily.artistTopArtist
            ? '${facts.title} now has ${facts.streamsText} on Sonus.'
            : sentences.any((sentence) => sentence.startsWith(it))
            ? 'It now has ${facts.streamsText} on Sonus.'
            : '$it now has ${facts.streamsText} on Sonus.',
      );
    }

    if (sentences.isEmpty) return null;
    return sentences.take(2).join(' ');
  }

  static String _kicker(MomentFamily family, MomentFacts facts) {
    switch (family) {
      case MomentFamily.artistTopArtist:
        return 'Your artists';
      case MomentFamily.songStreamMilestone ||
          MomentFamily.releaseStreamMilestone ||
          MomentFamily.artistStreamMilestone:
        return 'Streaming milestone';
      default:
        return facts.weekly ? 'Weekly ${facts.chartName}' : facts.chartName;
    }
  }

  static String _status(MomentFamily family) => switch (family) {
    MomentFamily.songDebutNumberOne ||
    MomentFamily.releaseDebutNumberOne => '#1 DEBUT',
    MomentFamily.songFirstNumberOne ||
    MomentFamily.releaseReachesNumberOne ||
    MomentFamily.songSelfReplacement ||
    MomentFamily.releaseSelfReplacement => 'NUMBER ONE',
    MomentFamily.songReturnsToNumberOne ||
    MomentFamily.releaseReturnsToNumberOne => 'BACK AT #1',
    MomentFamily.artistFirstNumberOne ||
    MomentFamily.artistFirstNumberOneRelease => 'FIRST #1',
    MomentFamily.artistNthNumberOne ||
    MomentFamily.artistNthNumberOneRelease ||
    MomentFamily.artistRepeatNumberOne ||
    MomentFamily.artistRepeatNumberOneRelease => '#1 HIT',
    MomentFamily.songDebutTop10 ||
    MomentFamily.songDebut ||
    MomentFamily.songBubblingUnderDebut ||
    MomentFamily.releaseDebut => 'DEBUT',
    MomentFamily.songHot100Breakthrough => 'HOT 100 BREAKTHROUGH',
    MomentFamily.songNewPeak ||
    MomentFamily.releaseNewPeak ||
    MomentFamily.songFirstThreshold ||
    MomentFamily.releaseFirstThreshold ||
    MomentFamily.songThresholds ||
    MomentFamily.releaseThresholds => 'NEW PEAK',
    MomentFamily.songPeakMatch => 'PEAK MATCH',
    MomentFamily.songBigClimb => 'BIG CLIMB',
    MomentFamily.songBiggestGainer => 'BIGGEST GAINER',
    MomentFamily.songReentry || MomentFamily.releaseReentry => 'RE-ENTRY',
    MomentFamily.songStreamMilestone ||
    MomentFamily.releaseStreamMilestone ||
    MomentFamily.artistStreamMilestone => 'MILESTONE',
    MomentFamily.songWeeksMilestone ||
    MomentFamily.releaseWeeksMilestone => 'LONGEVITY',
    MomentFamily.artistFirstHot100 => 'FIRST HOT 100 ENTRY',
    MomentFamily.artistFirstTop10 => 'FIRST TOP 10',
    MomentFamily.artistNthTop10 => 'TOP 10 HIT',
    MomentFamily.artistTopArtist => 'TOP ARTIST',
    MomentFamily.artistSimultaneous ||
    MomentFamily.artistSimultaneousReleases => 'RECORD',
  };

  /// Who writes a story under the SN-50 rules (F-Q28), by its character
  /// rather than an even split; earlier stories keep the publisher they
  /// were first published with. When the family has no headline in that
  /// voice that fits, the other publisher's headline is used.
  ///
  /// - **Sonus Daily**, measured and factual: debuts below the Top 10 and
  ///   Bubbling Under arrivals, re-entries, chart zones, peak matches,
  ///   streaming and longevity milestones, an artist's first Hot 100 entry,
  ///   counted career records (nth Top 10, nth or repeat #1) and roundups.
  /// - **PulsePop**, expressive and energetic: #1 arrivals, returns and
  ///   self-replacements, Top 10 debuts, new peaks, big climbs, the biggest
  ///   gainer, Hot 100 breakthroughs, an artist's first Top 10 or #1, and a
  ///   new top artist.
  static MomentPublisher publisherFor(MomentFamily family) => switch (family) {
    MomentFamily.songDebut ||
    MomentFamily.songBubblingUnderDebut ||
    MomentFamily.songReentry ||
    MomentFamily.songPeakMatch ||
    MomentFamily.songStreamMilestone ||
    MomentFamily.songWeeksMilestone ||
    MomentFamily.songFirstThreshold ||
    MomentFamily.songThresholds ||
    MomentFamily.releaseDebut ||
    MomentFamily.releaseReentry ||
    MomentFamily.releaseStreamMilestone ||
    MomentFamily.releaseWeeksMilestone ||
    MomentFamily.releaseFirstThreshold ||
    MomentFamily.releaseThresholds ||
    MomentFamily.artistFirstHot100 ||
    MomentFamily.artistNthTop10 ||
    MomentFamily.artistNthNumberOne ||
    MomentFamily.artistNthNumberOneRelease ||
    MomentFamily.artistRepeatNumberOne ||
    MomentFamily.artistRepeatNumberOneRelease ||
    MomentFamily.artistStreamMilestone ||
    MomentFamily.artistSimultaneous ||
    MomentFamily.artistSimultaneousReleases => MomentPublisher.sonusDaily,
    MomentFamily.songDebutNumberOne ||
    MomentFamily.songDebutTop10 ||
    MomentFamily.songHot100Breakthrough ||
    MomentFamily.songFirstNumberOne ||
    MomentFamily.songReturnsToNumberOne ||
    MomentFamily.songNewPeak ||
    MomentFamily.songBigClimb ||
    MomentFamily.songBiggestGainer ||
    MomentFamily.songSelfReplacement ||
    MomentFamily.releaseDebutNumberOne ||
    MomentFamily.releaseReachesNumberOne ||
    MomentFamily.releaseReturnsToNumberOne ||
    MomentFamily.releaseNewPeak ||
    MomentFamily.releaseSelfReplacement ||
    MomentFamily.artistFirstTop10 ||
    MomentFamily.artistFirstNumberOne ||
    MomentFamily.artistFirstNumberOneRelease ||
    MomentFamily.artistTopArtist => MomentPublisher.pulsePop,
  };

  /// Per finalized week and chart, the story with the largest verified
  /// climb, when it climbed at least [biggestGainerMinimumPlaces].
  static Set<String> _biggestGainers(
    List<ChartMomentFeedItem> items,
    ChartMomentRules rules,
  ) {
    final best = <String, (ChartMomentFeedItem, int)>{};
    for (final item in items) {
      // SN-50: a climb counts even when a new peak or zone leads its story.
      final climbed =
          rules.appliesTo(
            scope: item.scope,
            occurredAt: item.occurredAt,
            weekStartUtc: item.weekStartUtc,
          )
          ? item.contains(ChartMomentEventType.rankRise)
          : item.dominantEventType == ChartMomentEventType.rankRise;
      if (item.scope != ChartMomentScope.finalized || !climbed) continue;
      final rise = item.events.firstWhere(
        (event) => event.eventType == ChartMomentEventType.rankRise,
      );
      // SN-50 BUG-04: a move from Bubbling Under into the Hot 100 is a
      // Hot 100 arrival, not a climb on it (E-Q1).
      if (_crossesIntoHot100(rise) &&
          rules.appliesTo(
            scope: item.scope,
            occurredAt: item.occurredAt,
            weekStartUtc: item.weekStartUtc,
          )) {
        continue;
      }
      final places = rise.movementDistance ?? 0;
      if (places < biggestGainerMinimumPlaces) continue;
      final key =
          '${item.chartType.name}:${item.weekStartUtc.millisecondsSinceEpoch}';
      final current = best[key];
      if (current == null ||
          places > current.$2 ||
          (places == current.$2 && item.id.compareTo(current.$1.id) < 0)) {
        best[key] = (item, places);
      }
    }
    return {for (final entry in best.values) entry.$1.id};
  }

  static bool _crossesIntoHot100(ChartMomentEvent rise) {
    const limit = ChartRankingEngine.officialChartLimit;
    final before = rise.previousRank;
    final now = rise.currentRank;
    return rise.chartType == ChartType.songs &&
        before != null &&
        now != null &&
        before > limit &&
        now <= limit;
  }

  /// FNV-1a: the same text always gives the same number, on every device
  /// and every run.
  static int _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
