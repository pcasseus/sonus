// App Update 1.2, REF-19: how artist-dominance Moments are told. Until
// their lines are approved the artist roundup is told exactly as before;
// the draft lines are checked against the copy rules and rendered as the
// sample output for approval.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';

final _weekStart = DateTime.utc(2026, 11, 8);
final _weekEnd = DateTime.utc(2026, 11, 15);

const _dominanceFamilies = {
  MomentFamily.artistChartSweep,
  MomentFamily.artistTop10Presence,
  MomentFamily.artistHot100Presence,
};

ChartMomentEvent _simultaneous({
  required int threshold,
  required int count,
  String? source,
}) {
  final key = 'k:$threshold:$count:${source ?? 'week'}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source ?? 'week',
    chartType: ChartType.songs,
    scope: ChartMomentScope.finalized,
    eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
    entity: const ChartEntitySnapshot(
      entityId: 'song-1',
      title: 'Paper Moon',
      artistId: 'mira',
      artistName: 'Mira Vale',
    ),
    relatedEntity: const ChartEntitySnapshot(
      entityId: 'song-2',
      title: 'Glass Harbor',
      artistId: 'mira',
      artistName: 'Mira Vale',
    ),
    weekStartUtc: _weekStart,
    weekEndUtc: _weekEnd,
    occurredAt: _weekEnd,
    createdAt: _weekEnd,
    currentRank: 1,
    threshold: threshold,
    milestoneValue: count,
  );
}

ChartMomentEvent _dominance(ArtistDominanceKind kind, int tier, int count) =>
    _simultaneous(
      threshold: kind.zoneFor(tier),
      count: count,
      source: ArtistDominance.sourceIdFor(
        kind,
        tier,
        DominanceContext.none,
        'week',
      ),
    );

MomentFacts _facts({required int threshold, required int count}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: true,
  refined: true,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 1,
  threshold: threshold,
  count: count,
);

Map<String, String> _drafts(MomentFamily family, MomentFacts facts) => {
  for (final draft in RefinedHeadlineCatalog.artistDominanceDrafts)
    if (draft.family == family) draft.variant.id: draft.variant.build(facts),
};

void main() {
  group('the feed', () {
    test('a dominance row joins the artist story it repeats, and the row '
        'recorded beside it leads', () {
      final legacy = _simultaneous(threshold: 3, count: 3);
      final items = const ChartMomentFeedAggregator().aggregate([
        _dominance(ArtistDominanceKind.sweep, 3, 3),
        legacy,
        _simultaneous(threshold: 10, count: 3),
      ]);
      expect(items, hasLength(1), reason: 'one artist story for the week');
      expect(items.single.events.first, same(legacy));
    });
  });

  group('the story planner', () {
    final withDominance = const ChartMomentFeedAggregator().aggregate([
      _simultaneous(threshold: 5, count: 3),
      _simultaneous(threshold: 10, count: 5),
      _simultaneous(threshold: 100, count: 12),
      _dominance(ArtistDominanceKind.top10, 5, 5),
      _dominance(ArtistDominanceKind.hot100, 10, 12),
    ]).single;
    final without = const ChartMomentFeedAggregator().aggregate([
      _simultaneous(threshold: 5, count: 3),
      _simultaneous(threshold: 10, count: 5),
      _simultaneous(threshold: 100, count: 12),
    ]).single;

    test('until the lines are approved, the roundup is told exactly as '
        'before', () {
      expect(MomentStoryPlanner.dominanceStory(withDominance), isNull);
      List<(String, MomentFamily, int?, int?)> told(item) => [
        for (final story in MomentStoryPlanner([
          item,
        ], biggestGainers: const {}).plan(item))
          (
            story.item.id,
            story.family,
            story.item.events.first.threshold,
            story.item.events.first.milestoneValue,
          ),
      ];
      expect(told(withDominance), told(without));
      expect(told(without).single.$2, MomentFamily.artistSimultaneous);
    });

    test('once approved, the most notable dominance is the one artist '
        'story: a sweep, then the Top 10, then the Hot 100', () {
      final (family, event) = MomentStoryPlanner.dominanceStory(
        withDominance,
        approved: _dominanceFamilies,
      )!;
      expect(family, MomentFamily.artistTop10Presence);
      expect((event.threshold, event.milestoneValue), (10, 5));

      final sweep = const ChartMomentFeedAggregator().aggregate([
        _dominance(ArtistDominanceKind.hot100, 5, 5),
        _dominance(ArtistDominanceKind.sweep, 5, 5),
      ]).single;
      expect(
        MomentStoryPlanner.dominanceStory(
          sweep,
          approved: _dominanceFamilies,
        )!.$1,
        MomentFamily.artistChartSweep,
      );
      expect(
        MomentStoryPlanner.dominanceStory(
          without,
          approved: _dominanceFamilies,
        ),
        isNull,
      );
    });
  });

  group('draft headlines', () {
    test('are unapproved and change nothing yet', () {
      expect(
        RefinedHeadlineCatalog.artistDominanceDrafts.every((d) => !d.approved),
        isTrue,
      );
      expect(
        MomentHeadlines.approvedFamilies.intersection(_dominanceFamilies),
        isEmpty,
      );
      for (final family in _dominanceFamilies) {
        expect(
          RefinedHeadlineCatalog.standard.of(
            family,
            _facts(threshold: 10, count: 5),
          ),
          isEmpty,
        );
        expect(MomentHeadlines.legacyOf(family), isEmpty);
      }
    });

    test('each family has 6 Sonus Daily and 6 PulsePop lines that pass the '
        'copy rules', () {
      const banned = [
        'lifetime',
        'summit',
        'all-time',
        'points',
        'this week',
        'last week',
        'null',
      ];
      final facts = _facts(threshold: 5, count: 5);
      for (final family in _dominanceFamilies) {
        final drafts = [
          for (final d in RefinedHeadlineCatalog.artistDominanceDrafts)
            if (d.family == family) d.variant,
        ];
        for (final publisher in MomentPublisher.values) {
          expect(
            {
              for (final v in drafts)
                if (v.publisher == publisher) v.build(facts),
            },
            hasLength(6),
            reason: '${family.name} ${publisher.name}',
          );
        }
        for (final v in drafts) {
          expect(v.fits(facts), isTrue, reason: v.id);
          final text = v.build(facts);
          for (final word in banned) {
            expect(text.toLowerCase(), isNot(contains(word)), reason: v.id);
          }
          expect(text, isNot(contains('  ')), reason: v.id);
          expect(text, matches(RegExp(r'[.!]$')), reason: v.id);
          expect(text, contains('Mira Vale'), reason: v.id);
          expect(text, contains('5'), reason: v.id);
        }
      }
    });

    test('sample output', () {
      expect(
        _drafts(MomentFamily.artistChartSweep, _facts(threshold: 3, count: 3)),
        {
          'artist-sweep-d1':
              'Mira Vale sweeps the Top 3 of the weekly Sonus Hot 100, '
              'holding every spot from #1 to #3.',
          'artist-sweep-d2':
              'From #1 to #3, the weekly Sonus Hot 100 belongs to Mira Vale.',
          'artist-sweep-d3':
              'Every song from #1 to #3 on the weekly Sonus Hot 100 is by '
              'Mira Vale.',
          'artist-sweep-d4':
              'Mira Vale holds all of the Top 3 on the weekly Sonus Hot 100.',
          'artist-sweep-d5':
              'The Top 3 of the weekly Sonus Hot 100 is all Mira Vale, from '
              '#1 down to #3.',
          'artist-sweep-d6':
              'Mira Vale occupies #1 through #3 on the weekly Sonus Hot 100, '
              'a clean sweep.',
          'artist-sweep-p1':
              'Clean sweep: Mira Vale owns the entire Top 3 on the weekly '
              'Sonus Hot 100!',
          'artist-sweep-p2': 'Every spot from #1 to #3 belongs to Mira Vale!',
          'artist-sweep-p3':
              'Top 3? All Mira Vale. A total sweep on the weekly Sonus Hot '
              '100!',
          'artist-sweep-p4':
              'Mira Vale runs the table: #1 to #3 on the weekly Sonus Hot '
              '100!',
          'artist-sweep-p5':
              'Nobody else gets a look in: Mira Vale fills the Top 3 of the '
              'weekly Sonus Hot 100!',
          'artist-sweep-p6':
              'Mira Vale takes every spot from #1 to #3 on the weekly Sonus '
              'Hot 100!',
        },
      );
      expect(
        _drafts(
          MomentFamily.artistTop10Presence,
          _facts(threshold: 10, count: 5),
        ),
        {
          'artist-top10-count-d1':
              'Mira Vale has 5 songs in the Top 10 of the weekly Sonus Hot '
              '100.',
          'artist-top10-count-d2':
              '5 of the 10 biggest songs on the weekly Sonus Hot 100 are by '
              'Mira Vale.',
          'artist-top10-count-d3':
              'Mira Vale places 5 songs inside the Top 10 of the weekly Sonus '
              'Hot 100.',
          'artist-top10-count-d4':
              'The Top 10 of the weekly Sonus Hot 100 includes 5 songs by '
              'Mira Vale.',
          'artist-top10-count-d5':
              'Mira Vale holds 5 of the Top 10 spots on the weekly Sonus Hot '
              '100.',
          'artist-top10-count-d6':
              'Mira Vale counts 5 songs among the Top 10 of the weekly Sonus '
              'Hot 100.',
          'artist-top10-count-p1':
              'Mira Vale takes over the Top 10: 5 songs on the weekly Sonus '
              'Hot 100!',
          'artist-top10-count-p2':
              '5 songs in the Top 10! Mira Vale is everywhere on the weekly '
              'Sonus Hot 100.',
          'artist-top10-count-p3':
              'The Top 10 is crowded with Mira Vale: 5 songs on the weekly '
              'Sonus Hot 100!',
          'artist-top10-count-p4':
              'Mira Vale stacks the Top 10 of the weekly Sonus Hot 100 with 5 '
              'songs!',
          'artist-top10-count-p5':
              'Top 10 takeover: 5 songs by Mira Vale on the weekly Sonus Hot '
              '100!',
          'artist-top10-count-p6':
              'Mira Vale claims 5 of the Top 10 spots on the weekly Sonus Hot '
              '100!',
        },
      );
      expect(
        _drafts(
          MomentFamily.artistHot100Presence,
          _facts(threshold: 100, count: 12),
        ),
        {
          'artist-hot100-count-d1':
              'Mira Vale has 12 songs on the weekly Sonus Hot 100 at the same '
              'time.',
          'artist-hot100-count-d2':
              '12 songs by Mira Vale chart together on the weekly Sonus Hot '
              '100.',
          'artist-hot100-count-d3':
              'Mira Vale places 12 songs on the weekly Sonus Hot 100 in one '
              'week.',
          'artist-hot100-count-d4':
              '12 spots on the weekly Sonus Hot 100 belong to Mira Vale.',
          'artist-hot100-count-d5':
              'Mira Vale charts 12 songs at once on the weekly Sonus Hot 100.',
          'artist-hot100-count-d6':
              'Mira Vale is represented by 12 songs on the weekly Sonus Hot '
              '100.',
          'artist-hot100-count-p1':
              'Mira Vale fills 12 spots on the weekly Sonus Hot 100!',
          'artist-hot100-count-p2':
              '12 songs at once! Mira Vale is all over the weekly Sonus Hot '
              '100.',
          'artist-hot100-count-p3':
              'Mira Vale floods the weekly Sonus Hot 100 with 12 songs!',
          'artist-hot100-count-p4':
              'Count them: 12 songs by Mira Vale on the weekly Sonus Hot 100!',
          'artist-hot100-count-p5':
              'Mira Vale is everywhere: 12 songs on the weekly Sonus Hot 100!',
          'artist-hot100-count-p6':
              'Mira Vale lands 12 songs on the weekly Sonus Hot 100 at once!',
        },
      );
    });
  });
}
