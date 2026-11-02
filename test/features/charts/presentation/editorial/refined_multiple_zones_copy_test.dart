// SN-50 Batch 9 (contract §6.2): songThresholds and releaseThresholds, 6
// Sonus Daily + 6 PulsePop lines each, approved. Movement wording needs a
// real climb, and the five longer Sonus Daily lines that omit the chart
// rely on the card kicker for it.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// Sonus Daily lines that do not name the chart (contract §10 item 3).
const _chartless = {
  'song-zones-d1',
  'song-zones-d4',
  'release-zones-d1',
  'release-zones-d4',
  'release-zones-d5',
};

MomentFacts _song({int? previousRank = 80}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: true,
  refined: true,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 38,
  previousRank: previousRank,
  thresholds: const [75, 50, 40],
);

MomentFacts _release({int? previousRank = 60}) => MomentFacts(
  chartType: ChartType.albums,
  weekly: true,
  refined: true,
  title: 'Night Signals',
  artist: 'Mira Vale',
  format: ReleaseFormat.album,
  rank: 27,
  previousRank: previousRank,
  thresholds: const [50, 40, 30],
);

Map<String, String> _render(MomentFamily family, MomentFacts facts) => {
  for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
    if (v.fits(facts)) v.id: v.build(facts),
};

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Mira Vale';
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> guestsOf(String songId) => const [];

  @override
  List<String> featuredOf(String songId) => const [];
  @override
  String? artistIdNamed(String name) => null;
  @override
  String? songCover(String songId) => null;
  @override
  String? releaseCover(String albumId) => null;
  @override
  String? currentSongCover(String songId) => null;
  @override
  String? currentReleaseCover(String albumId) => null;
  @override
  String? artistPortrait(String artistId) => null;
}

/// One move that first enters several zones at once.
List<ChartMomentEvent> _zones(
  ChartType type,
  ChartMomentScope scope,
  String id, {
  required int from,
  required int to,
  required List<int> zones,
}) => [
  for (final zone in zones)
    ChartMomentEvent(
      id: '${scope.name}|$id|$zone',
      deduplicationKey: '${scope.name}|$id|$zone',
      sourceId: id,
      chartType: type,
      scope: scope,
      eventType: ChartMomentEventType.firstThresholdEntry,
      entity: ChartEntitySnapshot(
        entityId: id,
        title: 'Title $id',
        artistId: 'mira',
        artistName: 'Mira Vale',
      ),
      weekStartUtc: DateTime.utc(2026, 10, 19),
      weekEndUtc: DateTime.utc(2026, 10, 26),
      occurredAt: DateTime.utc(2026, 10, 26, 12),
      createdAt: DateTime.utc(2026, 10, 26, 12),
      currentRank: to,
      previousRank: from,
      threshold: zone,
    ),
];

void main() {
  group('SN-50 Batch 9: multiple-zone families', () {
    test('songThresholds renders all twelve approved lines', () {
      expect(_render(MomentFamily.songThresholds, _song()), {
        'song-zones-d1':
            '"Paper Moon" by Mira Vale moves into the Top 75, Top 50 and Top 40 '
            'for the first time, now at #38.',
        'song-zones-p1':
            'Up and through: "Paper Moon" by Mira Vale enters the Top 75, Top 50 '
            'and Top 40 at #38.',
        'song-zones-d2':
            '"Paper Moon" by Mira Vale enters the Top 75, Top 50 and Top 40 of '
            'the weekly Sonus Hot 100 in one move, reaching #38.',
        'song-zones-d3':
            'At #38 on the weekly Sonus Hot 100, "Paper Moon" by Mira Vale is in '
            'the Top 75, Top 50 and Top 40 for the first time.',
        'song-zones-d4':
            '"Paper Moon" by Mira Vale reaches #38, its first time in the Top 75, '
            'Top 50 and Top 40.',
        'song-zones-d5':
            'A move to #38 takes "Paper Moon" by Mira Vale into the Top 75, Top '
            '50 and Top 40 of the weekly Sonus Hot 100 for the first time.',
        'song-zones-d6':
            '"Paper Moon" by Mira Vale records first entries into the Top 75, '
            'Top 50 and Top 40, at #38 on the weekly Sonus Hot 100.',
        'song-zones-p2':
            'Zone after zone: "Paper Moon" is now in the Top 75, Top 50 and Top '
            '40, at #38!',
        'song-zones-p3':
            'Big move for "Paper Moon" by Mira Vale: into the Top 75, Top 50 and '
            'Top 40 at #38.',
        'song-zones-p4':
            '"Paper Moon" enters the Top 75, Top 50 and Top 40 all at once, '
            'landing at #38.',
        'song-zones-p5':
            'New heights for "Paper Moon": the Top 75, Top 50 and Top 40, all for '
            'the first time, at #38.',
        'song-zones-p6':
            'Straight into the Top 75, Top 50 and Top 40: "Paper Moon" by Mira '
            'Vale reaches #38.',
      });
    });

    test('releaseThresholds renders all twelve approved lines', () {
      expect(_render(MomentFamily.releaseThresholds, _release()), {
        'release-zones-d1':
            'The album Night Signals by Mira Vale moves into the Top 50, Top 40 '
            'and Top 30 for the first time, now at #27.',
        'release-zones-p1':
            'Night Signals by Mira Vale breaks into the Top 50, Top 40 and Top '
            '30 in one move, landing at #27.',
        'release-zones-d2':
            'The album Night Signals by Mira Vale reaches #27 on the weekly '
            'Sonus Albums & EPs chart, entering the Top 50, Top 40 and Top 30 '
            'for the first time.',
        'release-zones-d3':
            'In one move, Night Signals by Mira Vale enters the Top 50, Top 40 '
            'and Top 30 of the weekly Sonus Albums & EPs chart, at #27.',
        'release-zones-d4':
            'Night Signals by Mira Vale is in the Top 50, Top 40 and Top 30 for '
            'the first time, a new best for the album at #27.',
        'release-zones-d5':
            'At #27, the album Night Signals by Mira Vale sits in the Top 50, '
            'Top 40 and Top 30 for the first time.',
        'release-zones-d6':
            'First entries into the Top 50, Top 40 and Top 30 for the album '
            'Night Signals by Mira Vale, now #27 on the weekly Sonus Albums & '
            'EPs chart.',
        'release-zones-p2':
            'Night Signals storms into the Top 50, Top 40 and Top 30 at #27!',
        'release-zones-p3':
            'Several firsts at once for the album Night Signals: the Top 50, Top '
            '40 and Top 30, at #27.',
        'release-zones-p4':
            'Up, up and in: the album Night Signals lands in the Top 50, Top 40 '
            'and Top 30 at #27.',
        'release-zones-p5':
            "Mira Vale's album Night Signals breaks new ground: the Top 50, Top "
            '40 and Top 30, at #27.',
        'release-zones-p6':
            'Landmark move for Night Signals: into the Top 50, Top 40 and Top 30 '
            'at #27.',
      });
    });

    test(
      'without a climb, no movement wording; both publishers keep lines',
      () {
        for (final (family, facts, moving) in [
          (
            MomentFamily.songThresholds,
            _song(previousRank: null),
            {
              'song-zones-d1',
              'song-zones-p1',
              'song-zones-d5',
              'song-zones-p2',
              'song-zones-p3',
            },
          ),
          (
            MomentFamily.releaseThresholds,
            _release(previousRank: null),
            {
              'release-zones-d1',
              'release-zones-p2',
              'release-zones-p4',
              'release-zones-p6',
            },
          ),
        ]) {
          final lines = [
            for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
              if (v.fits(facts)) v,
          ];
          expect(
            {for (final v in lines) v.id}.intersection(moving),
            isEmpty,
            reason: family.name,
          );
          for (final publisher in MomentPublisher.values) {
            expect(lines.where((v) => v.publisher == publisher), isNotEmpty);
          }
        }
      },
    );

    test('the kicker names the chart for every zone story, including the '
        'five lines that omit it', () {
      final desk = MomentEditorialDesk(
        lookups: const _Lookups(),
        rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
      );
      final seen = <String>{};
      for (final (type, zones, from, to, weeklyKicker, careerKicker) in [
        (
          ChartType.songs,
          const [75, 50, 40],
          80,
          38,
          'Weekly Sonus Hot 100',
          'Sonus Hot 100',
        ),
        (
          ChartType.albums,
          const [50, 40, 30],
          60,
          27,
          'Weekly Sonus Albums & EPs',
          'Sonus Albums & EPs',
        ),
      ]) {
        for (final scope in [
          ChartMomentScope.finalized,
          ChartMomentScope.allTime,
        ]) {
          for (var i = 0; i < 60; i++) {
            final stories = desk.compose(
              const ChartMomentFeedAggregator().aggregate(
                _zones(
                  type,
                  scope,
                  '${type.name}-$i',
                  from: from,
                  to: to,
                  zones: zones,
                ),
              ),
            );
            final story = stories.singleWhere(
              (s) =>
                  s.family == MomentFamily.songThresholds ||
                  s.family == MomentFamily.releaseThresholds,
            );
            expect(
              story.kicker,
              scope == ChartMomentScope.finalized ? weeklyKicker : careerKicker,
              reason: story.variantId,
            );
            seen.add(story.variantId);
          }
        }
      }
      // Sonus Daily tells these stories, so chart-less lines are picked.
      expect(seen.intersection(_chartless), isNotEmpty);
    });

    test('both families are approved', () {
      expect(
        MomentHeadlines.approvedFamilies,
        containsAll([
          MomentFamily.songThresholds,
          MomentFamily.releaseThresholds,
        ]),
      );
    });
  });
}
