import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';
import 'moment_publisher.dart';
import 'moment_facts.dart';
import 'moment_family.dart';
import 'moment_headlines.dart';
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
    this.tag,
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

  /// For example "SONUS HOT 100" or "SONUS BUBBLING UNDER".
  final String kicker;

  /// The achievement badge, for example "NUMBER ONE".
  final String status;

  /// The chart position badge, for example "BUBBLING UNDER #106".
  final String? tag;
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
///   kept, so later plays never remove a story already shown.
class MomentEditorialDesk {
  const MomentEditorialDesk({
    required this.lookups,
    this.minorStoriesPerDay = 3,
  });

  final MomentLookups lookups;
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
    final gainers = _biggestGainers(chronological);

    final minorPerDay = <String, int>{};
    final stories = <MomentStory>[];
    String? previousVariant;

    for (final item in chronological) {
      final family = MomentFamily.of(
        item,
        biggestGainer: gainers.contains(item.id),
      );
      if (family == null) continue;

      final facts = MomentFacts.of(item, lookups);
      if (family.tierFor(facts.rank) == MomentTier.minor) {
        final local = item.occurredAt.toLocal();
        final day = '${local.year}-${local.month}-${local.day}';
        final count = minorPerDay[day] ?? 0;
        if (count >= minorStoriesPerDay) continue;
        minorPerDay[day] = count + 1;
      }

      final story = _write(item, family, facts, previousVariant);
      previousVariant = story.variantId;
      stories.add(story);
    }

    return List.unmodifiable(stories.reversed);
  }

  MomentStory _write(
    ChartMomentFeedItem item,
    MomentFamily family,
    MomentFacts facts,
    String? previousVariant,
  ) {
    final variants = MomentHeadlines.of(family);
    final publisher = _hash('${item.id}|publisher').isEven
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
      tag: _tag(family, facts),
      rank: family == MomentFamily.artistTopArtist ? 1 : facts.rank,
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
    if (climbs &&
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
    // A first stream is what every debut has; it is not worth a sentence.
    if (streams != null &&
        streams > 1 &&
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
    MomentFamily.releaseReachesNumberOne => 'NUMBER ONE',
    MomentFamily.songReturnsToNumberOne ||
    MomentFamily.releaseReturnsToNumberOne => 'BACK AT #1',
    MomentFamily.artistFirstNumberOne ||
    MomentFamily.artistFirstNumberOneRelease => 'FIRST #1',
    MomentFamily.artistNthNumberOne ||
    MomentFamily.artistNthNumberOneRelease => '#1 HIT',
    MomentFamily.songDebutTop10 ||
    MomentFamily.songDebut ||
    MomentFamily.songBubblingUnderDebut ||
    MomentFamily.releaseDebut => 'DEBUT',
    MomentFamily.songHot100Breakthrough => 'HOT 100 BREAKTHROUGH',
    MomentFamily.songNewPeak || MomentFamily.releaseNewPeak => 'NEW PEAK',
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
    MomentFamily.artistSimultaneous => 'RECORD',
  };

  static String? _tag(MomentFamily family, MomentFacts facts) {
    if (family == MomentFamily.artistTopArtist) return 'ARTISTS #1';
    final rank = facts.rank;
    if (rank == null) return null;
    final chart = switch (facts.chartType) {
      ChartType.songs when facts.bubblingUnder => 'BUBBLING UNDER',
      ChartType.songs => 'HOT 100',
      ChartType.albums => 'ALBUMS & EPS',
    };
    return facts.weekly ? 'WEEKLY $chart #$rank' : '$chart #$rank';
  }

  /// Per finalized week and chart, the story with the largest verified
  /// climb, when it climbed at least [biggestGainerMinimumPlaces].
  static Set<String> _biggestGainers(List<ChartMomentFeedItem> items) {
    final best = <String, (ChartMomentFeedItem, int)>{};
    for (final item in items) {
      if (item.scope != ChartMomentScope.finalized ||
          item.dominantEventType != ChartMomentEventType.rankRise) {
        continue;
      }
      final rise = item.events.firstWhere(
        (event) => event.eventType == ChartMomentEventType.rankRise,
      );
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
