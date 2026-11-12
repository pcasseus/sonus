// App Update 1.2, REF-19: how artist-dominance Moments are told. Sweeps,
// Top 10 and Hot 100 presence are approved (2026-11-12): one story per
// artist-week, proportionate wording with the true count, "the Hot 100"
// under the card's "Weekly Sonus Hot 100" kicker, and a historical claim
// only where one was recorded. Joint chart control lines are drafts.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_joint_control.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/artist_dominance_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';

import 'moment_editorial_test.dart' show FakeLookups;

final _weekStart = DateTime.utc(2026, 11, 8);
final _weekEnd = DateTime.utc(2026, 11, 15);

const _dominanceFamilies = {
  MomentFamily.artistChartSweep,
  MomentFamily.artistTop10Presence,
  MomentFamily.artistHot100Presence,
};

final _lookups = FakeLookups(
  artists: {'mira': 'Mira Vale', 'juno': 'Juno Hart'},
);

ChartMomentEvent _simultaneous({
  required int threshold,
  required int count,
  String? source,
  String lead = 'Glass Hours',
  String second = 'Tidal',
  int leadRank = 1,
  String artistId = 'mira',
}) {
  final key = 'k:$threshold:$count:${source ?? 'week'}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source ?? 'week',
    chartType: ChartType.songs,
    scope: ChartMomentScope.finalized,
    eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
    entity: ChartEntitySnapshot(
      entityId: 'song-1',
      title: lead,
      artistId: artistId,
      artistName: 'Mira Vale',
    ),
    relatedEntity: ChartEntitySnapshot(
      entityId: 'song-2',
      title: second,
      artistId: artistId,
      artistName: 'Mira Vale',
    ),
    weekStartUtc: _weekStart,
    weekEndUtc: _weekEnd,
    occurredAt: _weekEnd,
    createdAt: _weekEnd,
    currentRank: leadRank,
    threshold: threshold,
    milestoneValue: count,
  );
}

ChartMomentEvent _dominance(
  ArtistDominanceKind kind,
  int tier,
  int count, {
  DominanceContext context = DominanceContext.none,
  String lead = 'Glass Hours',
  String second = 'Tidal',
  int leadRank = 1,
  String artistId = 'mira',
}) => _simultaneous(
  threshold: kind.zoneFor(tier),
  count: count,
  lead: lead,
  second: second,
  leadRank: leadRank,
  artistId: artistId,
  source: ArtistDominance.sourceIdFor(kind, tier, context, 'week'),
);

/// A joint control row for Mira, holding #1 ([lead]) or not.
ChartMomentEvent _joint(int positions, int count, {bool lead = true}) {
  final source = ArtistJointControl.sourceIdFor(positions, 'juno', 'week');
  return ChartMomentEvent(
    id: 'joint:$positions:$lead',
    deduplicationKey: 'joint:$positions:$lead',
    sourceId: source,
    chartType: ChartType.songs,
    scope: ChartMomentScope.finalized,
    eventType: ChartMomentEventType.artistSimultaneousThresholdSongs,
    entity: const ChartEntitySnapshot(
      entityId: 'song-1',
      title: 'Glass Hours',
      artistId: 'mira',
      artistName: 'Mira Vale',
    ),
    relatedEntity: const ChartEntitySnapshot(
      entityId: 'song-9',
      title: 'Low Tide',
      artistId: 'juno',
      artistName: 'Juno Hart',
    ),
    weekStartUtc: _weekStart,
    weekEndUtc: _weekEnd,
    occurredAt: _weekEnd,
    createdAt: _weekEnd,
    currentRank: lead ? 1 : 2,
    threshold: positions,
    milestoneValue: count,
  );
}

/// The facts of [event]'s dominance story, as the desk builds them.
MomentFacts _factsOf(ChartMomentEvent event, {MomentLookups? lookups}) =>
    MomentFacts.of(
      ChartMomentFeedAggregator.storyItem(id: 'story', events: [event]),
      lookups ?? _lookups,
      refined: true,
      catalogVersion: 1,
    );

/// Every approved (or, with [drafts], every) line of [family] that may
/// tell [event], by id.
Map<String, String> _render(
  MomentFamily family,
  ChartMomentEvent event, {
  MomentLookups? lookups,
}) {
  final facts = _factsOf(event, lookups: lookups);
  final approved = {
    for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
      if (v.fits(facts)) v.id: v.build(facts),
  };
  if (approved.isNotEmpty || family != MomentFamily.artistJointControl) {
    return approved;
  }
  return {
    for (final a in ArtistDominanceHeadlines.additions)
      if (a.family == family &&
          (a.when?.call(facts) ?? true) &&
          a.variant.fits(facts))
        a.variant.id: a.variant.build(facts),
  };
}

const _sweep = ArtistDominanceKind.sweep;
const _top10 = ArtistDominanceKind.top10;
const _hot100 = ArtistDominanceKind.hot100;

void main() {
  group('the feed', () {
    test('a dominance row joins the artist story it repeats, and the row '
        'recorded beside it leads', () {
      final legacy = _simultaneous(threshold: 3, count: 3);
      final items = const ChartMomentFeedAggregator().aggregate([
        _dominance(_sweep, 3, 3),
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
      _dominance(_top10, 5, 5),
      _dominance(_hot100, 10, 12),
    ]).single;
    final without = const ChartMomentFeedAggregator().aggregate([
      _simultaneous(threshold: 5, count: 3),
      _simultaneous(threshold: 10, count: 5),
      _simultaneous(threshold: 100, count: 12),
    ]).single;

    List<(MomentFamily, int?, int?)> told(ChartMomentFeedItem item) => [
      for (final story in MomentStoryPlanner([
        item,
      ], biggestGainers: const {}).plan(item))
        (
          story.family,
          story.item.events.first.threshold,
          story.item.events.first.milestoneValue,
        ),
    ];

    test('the most notable dominance is the one artist story: a sweep, then '
        'the Top 10, then the Hot 100', () {
      expect(told(withDominance), [(MomentFamily.artistTop10Presence, 10, 5)]);
      final sweep = const ChartMomentFeedAggregator().aggregate([
        _dominance(_hot100, 5, 5),
        _dominance(_sweep, 5, 5),
      ]).single;
      expect(told(sweep), [(MomentFamily.artistChartSweep, 5, 5)]);
    });

    test('a week without dominance keeps its roundup, exactly as before', () {
      expect(MomentStoryPlanner.dominanceStory(without), isNull);
      expect(told(without).single.$1, MomentFamily.artistSimultaneous);
    });

    test('a build without the approved lines tells the roundup as before', () {
      expect(
        MomentStoryPlanner.dominanceStory(
          withDominance,
          approved: MomentHeadlines.approvedFamilies.difference(
            _dominanceFamilies,
          ),
        ),
        isNull,
      );
    });
  });

  group('joint control and solo sweeps: one primary story, every fact '
      'kept', () {
    const all = {..._dominanceFamilies, MomentFamily.artistJointControl};
    (MomentFamily, ChartMomentEvent)? story(
      List<ChartMomentEvent> events, {
      Set<MomentFamily> approved = all,
    }) => MomentStoryPlanner.dominanceStory(
      const ChartMomentFeedAggregator().aggregate(events).single,
      approved: approved,
    );

    test('a solo sweep of the Top 3 or more leads', () {
      expect(
        story([_dominance(_sweep, 3, 3), _joint(5, 3)])?.$1,
        MomentFamily.artistChartSweep,
      );
    });

    test('joint control leads a Top 2 sweep and presence', () {
      expect(
        story([_dominance(_sweep, 2, 2), _joint(6, 3)])?.$1,
        MomentFamily.artistJointControl,
      );
      expect(
        story([_dominance(_top10, 3, 3), _joint(4, 2)])?.$1,
        MomentFamily.artistJointControl,
      );
    });

    test('told once, by the artist at #1; the partner tells its own '
        'facts', () {
      expect(
        story([_dominance(_top10, 3, 3), _joint(4, 2, lead: false)])?.$1,
        MomentFamily.artistTop10Presence,
      );
      expect(story([_joint(4, 2, lead: false)]), isNull);
    });

    test('this build passes joint control over: its lines are drafts', () {
      expect(
        story([_joint(5, 3)], approved: MomentHeadlines.approvedFamilies),
        isNull,
      );
      expect(
        story([
          _dominance(_sweep, 2, 2),
          _joint(5, 3),
        ], approved: MomentHeadlines.approvedFamilies)?.$1,
        MomentFamily.artistChartSweep,
      );
    });

    test('a joint row never leads the feed item over the row recorded '
        'beside it', () {
      final legacy = _simultaneous(threshold: 5, count: 3);
      final item = const ChartMomentFeedAggregator().aggregate([
        _joint(5, 3),
        legacy,
      ]).single;
      expect(item.events.first, same(legacy));
    });
  });

  group('approved lines', () {
    test('36 lines: 6 Sonus Daily and 6 Pulse Pop per family, approved; the '
        '12 joint control lines are drafts', () {
      for (final family in _dominanceFamilies) {
        final lines = [
          for (final a in ArtistDominanceHeadlines.additions)
            if (a.family == family) a,
        ];
        expect(lines, hasLength(12), reason: '$family');
        expect(lines.every((a) => a.approved), isTrue);
        for (final publisher in MomentPublisher.values) {
          expect(
            lines.where((a) => a.variant.publisher == publisher),
            hasLength(6),
          );
        }
      }
      final joint = [
        for (final a in ArtistDominanceHeadlines.additions)
          if (a.family == MomentFamily.artistJointControl) a,
      ];
      expect(joint, hasLength(12));
      expect(joint.every((a) => !a.approved), isTrue);
      expect(
        RefinedHeadlineCatalog.standard.of(
          MomentFamily.artistJointControl,
          _factsOf(_joint(5, 3)),
        ),
        isEmpty,
      );
    });

    test('sample output: every approved line, rendered', () {
      expect(_render(MomentFamily.artistChartSweep, _dominance(_sweep, 2, 2)), {
        'artist-sweep-d1': 'Mira Vale holds #1 and #2 on the Hot 100.',
        'artist-sweep-d2':
            'Mira Vale sweeps the Top 2 of the Hot 100, led by "Glass Hours" '
            'at #1.',
        'artist-sweep-d3':
            '"Glass Hours" leads a Top 2 sweep for Mira Vale on the Hot 100.',
        'artist-sweep-d4': "The Hot 100's Top 2 belongs entirely to Mira Vale.",
        'artist-sweep-d5':
            'Mira Vale occupies #1 and #2 on the Hot 100, with "Glass Hours" '
            'at #1 and "Tidal" at #2.',
        'artist-sweep-d6': 'Mira Vale completes a Top 2 sweep of the Hot 100.',
        'artist-sweep-p1': 'Mira Vale takes #1 and #2 on the Hot 100!',
        'artist-sweep-p2': 'A Top 2 sweep for Mira Vale, led by "Glass Hours"!',
        'artist-sweep-p3':
            '"Glass Hours" at #1, "Tidal" at #2: the top two spots all belong '
            'to Mira Vale!',
        'artist-sweep-p4': 'Mira Vale owns the Top 2 of the Hot 100!',
      });
      expect(
        _render(MomentFamily.artistChartSweep, _dominance(_sweep, 6, 6)),
        containsPair(
          'artist-sweep-p5',
          'Clean sweep! Mira Vale fills the entire Top 6!',
        ),
      );
      expect(
        _render(MomentFamily.artistChartSweep, _dominance(_sweep, 6, 6)),
        containsPair(
          'artist-sweep-p6',
          'No one else in the Top 6: Mira Vale holds every spot!',
        ),
      );

      expect(
        _render(
          MomentFamily.artistTop10Presence,
          _dominance(_top10, 3, 3, leadRank: 2),
        ),
        {
          'artist-top10-count-d1':
              'Mira Vale has 3 songs in the Top 10 of the Hot 100, led by '
              '"Glass Hours" at #2.',
          'artist-top10-count-d2':
              "Mira Vale places 3 songs in the Hot 100's Top 10.",
          'artist-top10-count-d3':
              "Three of the Hot 100's Top 10 songs are by Mira Vale.",
          'artist-top10-count-d4':
              'Mira Vale holds 3 of the 10 highest positions on the Hot 100.',
          'artist-top10-count-d5':
              "\"Glass Hours\" leads Mira Vale's 3 Top 10 songs on the Hot "
              '100.',
          'artist-top10-count-d6':
              "Mira Vale now has 3 songs inside the Hot 100's Top 10.",
          'artist-top10-count-p1': 'Mira Vale has 3 songs in the Top 10!',
          'artist-top10-count-p2': 'Three Top 10 songs at once for Mira Vale!',
          'artist-top10-count-p3':
              '"Glass Hours" leads the way as Mira Vale lands 3 songs in the '
              'Top 10!',
          'artist-top10-count-p4':
              'Mira Vale holds 3 of the 10 spots in the Top 10!',
        },
      );
      final six = _render(
        MomentFamily.artistTop10Presence,
        _dominance(_top10, 5, 6, leadRank: 2),
      );
      expect(
        six['artist-top10-count-p5'],
        'Mira Vale is all over the Top 10 with 6 songs!',
      );
      expect(
        six['artist-top10-count-p6'],
        'Top 10 takeover: 6 songs by Mira Vale!',
      );

      expect(
        _render(
          MomentFamily.artistHot100Presence,
          _dominance(_hot100, 5, 7, leadRank: 4),
        ),
        {
          'artist-hot100-count-d1':
              'Mira Vale has 7 songs on the Hot 100, led by "Glass Hours" at '
              '#4.',
          'artist-hot100-count-d2':
              'Mira Vale charts 7 songs at once on the Hot 100.',
          'artist-hot100-count-d3':
              'The Hot 100 includes 7 songs by Mira Vale.',
          'artist-hot100-count-d4':
              '"Glass Hours" leads 7 Hot 100 entries for Mira Vale.',
          'artist-hot100-count-d5':
              'Mira Vale accounts for 7 of the 100 songs on the Hot 100.',
          'artist-hot100-count-d6':
              'Mira Vale reaches 7 simultaneous Hot 100 entries.',
          'artist-hot100-count-p1': 'Mira Vale has 7 songs on the Hot 100!',
          'artist-hot100-count-p2':
              'Count them: 7 songs by Mira Vale on the Hot 100!',
          'artist-hot100-count-p3':
              'Mira Vale lands 7 songs on the Hot 100 at once!',
        },
      );
      final seventeen = _render(
        MomentFamily.artistHot100Presence,
        _dominance(_hot100, 15, 17, leadRank: 4),
      );
      expect(
        seventeen['artist-hot100-count-p4'],
        '"Glass Hours" leads a 17-song Hot 100 run for Mira Vale!',
      );
      expect(
        seventeen['artist-hot100-count-p5'],
        'Mira Vale is everywhere: 17 songs on the Hot 100!',
      );
      expect(
        seventeen['artist-hot100-count-p6'],
        'Mira Vale floods the Hot 100 with 17 songs!',
      );
    });

    test('Pulse Pop never overstates a modest achievement', () {
      final strong = {
        'artist-sweep-p5': (_sweep, 5),
        'artist-sweep-p6': (_sweep, 5),
        'artist-top10-count-p5': (_top10, 5),
        'artist-top10-count-p6': (_top10, 6),
        'artist-hot100-count-p4': (_hot100, 10),
        'artist-hot100-count-p5': (_hot100, 10),
        'artist-hot100-count-p6': (_hot100, 15),
      };
      for (final MapEntry(key: id, value: (kind, minimum)) in strong.entries) {
        final family = MomentStoryPlanner.familyOf(kind);
        ChartMomentEvent at(int size) => kind == _sweep
            ? _dominance(_sweep, size, size)
            : _dominance(
                kind,
                kind.tiers.lastWhere((t) => t <= size),
                size,
                leadRank: 2,
              );
        final below = kind == _sweep ? minimum - 1 : minimum - 1;
        if (below >= kind.tiers.first) {
          expect(
            _render(family, at(below)),
            isNot(contains(id)),
            reason: '$id at $below',
          );
        }
        expect(
          _render(family, at(minimum)),
          contains(id),
          reason: '$id at $minimum',
        );
      }
      for (final text in [
        ..._render(
          MomentFamily.artistTop10Presence,
          _dominance(_top10, 3, 4, leadRank: 2),
        ).values,
        ..._render(
          MomentFamily.artistHot100Presence,
          _dominance(_hot100, 5, 9, leadRank: 2),
        ).values,
        ..._render(
          MomentFamily.artistChartSweep,
          _dominance(_sweep, 4, 4),
        ).values,
      ]) {
        for (final word in [
          'takeover',
          'floods',
          'everywhere',
          'all over',
          'Clean sweep',
        ]) {
          expect(text, isNot(contains(word)), reason: text);
        }
      }
    });
  });

  group('historical claims, only as recorded', () {
    String told(MomentFamily family, ChartMomentEvent event, String id) =>
        _render(family, event)[id]!;

    test('each claim ends the line, scoped to Sonus Hot 100 history', () {
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            5,
            5,
            context: const DominanceContext(DominanceContextKind.chartFirst),
          ),
          'artist-sweep-d6',
        ),
        'Mira Vale completes a Top 5 sweep of the Hot 100, the first Top 5 '
        'sweep in Sonus Hot 100 history.',
      );
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            5,
            5,
            context: const DominanceContext(DominanceContextKind.chartFirst),
          ),
          'artist-sweep-p4',
        ),
        'Mira Vale owns the Top 5 of the Hot 100, a first for the Sonus Hot '
        '100!',
      );
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            3,
            3,
            context: const DominanceContext(DominanceContextKind.streak, 2),
          ),
          'artist-sweep-d1',
        ),
        'Mira Vale holds #1 through #3 on the Hot 100 for a second straight '
        'week.',
      );
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            3,
            3,
            context: const DominanceContext(DominanceContextKind.streak, 15),
          ),
          'artist-sweep-p1',
        ),
        'Mira Vale takes #1 through #3 on the Hot 100 for a 15th straight '
        'week!',
      );
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            4,
            4,
            context: const DominanceContext(DominanceContextKind.artistFirst),
          ),
          'artist-sweep-d2',
        ),
        'Mira Vale sweeps the Top 4 of the Hot 100, led by "Glass Hours" at '
        "#1, Mira Vale's first Top 4 sweep on the Sonus Hot 100.",
      );
      expect(
        told(
          MomentFamily.artistChartSweep,
          _dominance(
            _sweep,
            3,
            3,
            context: const DominanceContext(DominanceContextKind.repeat, 3),
          ),
          'artist-sweep-d6',
        ),
        'Mira Vale completes a Top 3 sweep of the Hot 100, '
        "Mira Vale's third Top 3 sweep on the Sonus Hot 100.",
      );
      expect(
        told(
          MomentFamily.artistTop10Presence,
          _dominance(
            _top10,
            5,
            6,
            leadRank: 2,
            context: const DominanceContext(DominanceContextKind.chartRecord),
          ),
          'artist-top10-count-d2',
        ),
        "Mira Vale places 6 songs in the Hot 100's Top 10, the most Top 10 "
        'songs any artist has held in Sonus Hot 100 history.',
      );
      expect(
        told(
          MomentFamily.artistTop10Presence,
          _dominance(
            _top10,
            5,
            5,
            leadRank: 2,
            context: const DominanceContext(
              DominanceContextKind.chartRecordTie,
            ),
          ),
          'artist-top10-count-p1',
        ),
        'Mira Vale has 5 songs in the Top 10, matching the Sonus Hot 100 '
        'record!',
      );
      expect(
        told(
          MomentFamily.artistHot100Presence,
          _dominance(
            _hot100,
            10,
            12,
            leadRank: 3,
            context: const DominanceContext(DominanceContextKind.personalBest),
          ),
          'artist-hot100-count-d4',
        ),
        '"Glass Hours" leads 12 Hot 100 entries for Mira Vale, a personal best '
        'for Mira Vale on the Sonus Hot 100.',
      );
      expect(
        told(
          MomentFamily.artistHot100Presence,
          _dominance(
            _hot100,
            15,
            17,
            leadRank: 3,
            context: const DominanceContext(DominanceContextKind.chartRecord),
          ),
          'artist-hot100-count-p6',
        ),
        'Mira Vale floods the Hot 100 with 17 songs, the most songs any '
        'artist has had on the Hot 100 at once in Sonus Hot 100 history!',
      );
    });

    test('a streak is never told by a line it would make ambiguous', () {
      final lines = _render(
        MomentFamily.artistChartSweep,
        _dominance(
          _sweep,
          3,
          3,
          context: const DominanceContext(DominanceContextKind.streak, 2),
        ),
      );
      for (final id in [
        'artist-sweep-d2',
        'artist-sweep-d5',
        'artist-sweep-p2',
      ]) {
        expect(lines, isNot(contains(id)));
      }
      expect(lines.length, greaterThanOrEqualTo(6));
      expect(lines.values, everyElement(contains('second straight week')));
    });

    test('nothing recorded, nothing claimed', () {
      for (final family in _dominanceFamilies) {
        final kind = switch (family) {
          MomentFamily.artistChartSweep => _sweep,
          MomentFamily.artistTop10Presence => _top10,
          _ => _hot100,
        };
        for (final text in _render(
          family,
          _dominance(kind, kind.tiers.first, kind.tiers.first, leadRank: 2),
        ).values) {
          for (final word in [
            'history',
            'record',
            'first',
            'straight',
            'personal',
            'ever',
            'all-time',
            'career',
          ]) {
            expect(text.toLowerCase(), isNot(contains(word)), reason: text);
          }
        }
      }
    });
  });

  group('every size, count, name and title renders cleanly', () {
    final names = {
      'mira': 'Mira Vale',
      'ss': 'Sam Smith',
      'odd': '  The\tNational  ',
      'quote': 'Florence + the Machine',
    };
    const titles = [
      'Glass Hours',
      'Say "Yes"',
      'Two\nLines',
      'Ünicode, Résumé & Co.',
    ];

    final cases = <(MomentFamily, ChartMomentEvent)>[
      for (final artistId in names.keys)
        for (final title in titles) ...[
          for (var n = 2; n <= 10; n++)
            for (final context in const [
              DominanceContext.none,
              DominanceContext(DominanceContextKind.chartFirst),
              DominanceContext(DominanceContextKind.artistFirst),
              DominanceContext(DominanceContextKind.streak, 5),
              DominanceContext(DominanceContextKind.repeat, 2),
            ])
              (
                MomentFamily.artistChartSweep,
                _dominance(
                  _sweep,
                  n,
                  n,
                  lead: title,
                  artistId: artistId,
                  context: context,
                ),
              ),
          for (final (tier, count) in const [
            (3, 3),
            (3, 4),
            (5, 5),
            (5, 9),
            (10, 10),
          ])
            (
              MomentFamily.artistTop10Presence,
              _dominance(
                _top10,
                tier,
                count,
                lead: title,
                leadRank: 2,
                artistId: artistId,
                context: const DominanceContext(
                  DominanceContextKind.chartRecord,
                ),
              ),
            ),
          for (final (tier, count) in const [
            (5, 5),
            (10, 14),
            (15, 15),
            (20, 37),
          ])
            (
              MomentFamily.artistHot100Presence,
              _dominance(
                _hot100,
                tier,
                count,
                lead: title,
                leadRank: 2,
                artistId: artistId,
                context: const DominanceContext(
                  DominanceContextKind.personalBest,
                ),
              ),
            ),
        ],
    ];

    test(
      '${cases.length} stories: grammatical, tidy and true to the facts',
      () {
        final lookups = FakeLookups(artists: names);
        for (final (family, event) in cases) {
          final lines = _render(family, event, lookups: lookups);
          expect(lines, isNotEmpty, reason: event.sourceId);
          final artist = names[event.entity.artistId]!
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          for (final MapEntry(key: id, value: text) in lines.entries) {
            final why = '$id: $text';
            expect(text, matches(RegExp(r'[.!]$')), reason: why);
            expect(text, isNot(matches(RegExp(r'^\d'))), reason: why);
            expect(text, isNot(contains('  ')), reason: why);
            expect(text, isNot(contains('\n')), reason: why);
            expect(text, isNot(contains('\t')), reason: why);
            expect(text, isNot(contains('null')), reason: why);
            expect(text, isNot(contains(r'$')), reason: why);
            expect(text, isNot(contains('weekly')), reason: why);
            expect(text, contains(artist), reason: why);
            // Sonus Daily always names the chart; Pulse Pop may leave it to
            // the card's "Weekly Sonus Hot 100" kicker.
            if (id.contains('-d')) {
              expect(text, contains('Hot 100'), reason: why);
            }
            expect('"'.allMatches(text).length.isEven, isTrue, reason: why);
            expect(text, isNot(contains('Top 2 spots')), reason: why);
            if (family == MomentFamily.artistChartSweep &&
                event.threshold == 2) {
              expect(text, isNot(contains('through #2')), reason: why);
            }
            if (family != MomentFamily.artistChartSweep) {
              // The true count, as digits or, starting a sentence, a word.
              const words = [
                'Three',
                'Four',
                'Five',
                'Six',
                'Seven',
                'Eight',
                'Nine',
                'Ten',
              ];
              final count = event.milestoneValue!;
              expect(
                text.contains('$count') ||
                    (count >= 3 &&
                        count <= 10 &&
                        text.startsWith(words[count - 3])),
                isTrue,
                reason: why,
              );
            }
          }
        }
      },
    );

    test('a title keeps its words; inner double quotes become single', () {
      final lines = _render(
        MomentFamily.artistChartSweep,
        _dominance(_sweep, 3, 3, lead: 'Say "Yes"\n(Live)'),
      );
      expect(
        lines['artist-sweep-d3'],
        '"Say \'Yes\' (Live)" leads a Top 3 sweep for Mira Vale on the Hot 100.',
      );
    });
  });

  group('the desk tells the approved story', () {
    test('one dominance story under the Weekly Sonus Hot 100 kicker, with a '
        'deterministic line', () {
      List<MomentStory> compose() =>
          MomentEditorialDesk(
            lookups: _lookups,
            rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
          ).compose(
            const ChartMomentFeedAggregator().aggregate([
              _simultaneous(threshold: 3, count: 3),
              _dominance(_sweep, 3, 3),
            ]),
          );
      final stories = compose();
      final story = stories.singleWhere(
        (s) => s.family == MomentFamily.artistChartSweep,
      );
      expect(story.kicker, 'Weekly Sonus Hot 100');
      expect(story.status, 'CHART SWEEP');
      expect(
        _render(MomentFamily.artistChartSweep, _dominance(_sweep, 3, 3)).values,
        contains(story.headline),
      );
      expect(
        stories.where((s) => s.family == MomentFamily.artistSimultaneous),
        isEmpty,
        reason: 'the roundup it replaces is not told as well',
      );
      expect(compose().map((s) => s.headline), stories.map((s) => s.headline));
    });
  });

  test('joint control drafts render for review', () {
    final lines = _render(MomentFamily.artistJointControl, _joint(5, 3));
    expect(
      lines['artist-joint-d1'],
      'Mira Vale and Juno Hart hold #1 through #5 on the Hot 100 between them.',
    );
    expect(
      lines['artist-joint-d3'],
      'Mira Vale (3) and Juno Hart (2) account for every song in the Top 5.',
    );
    expect(lines, isNot(contains('artist-joint-p5')), reason: 'Top 6 or more');
    expect(
      _render(MomentFamily.artistJointControl, _joint(6, 3)),
      contains('artist-joint-p5'),
    );
  });
}
