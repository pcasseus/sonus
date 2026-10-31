// SN-50 Batch 4 (contract §6.1 B and C, BU-001, BU-002, BU-010 to BU-015):
// refined wording for a first Hot 100 entry from Bubbling Under. The move
// is told across two charts, never as a Hot 100 climb, and the debut is the
// song's, never the artist's. The legacy F05 catalog is unchanged.
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
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

const _f05 = MomentFamily.songHot100Breakthrough;
const _weeklyOnly = {
  'song-break-d2',
  'song-break-d7',
  'song-break-d9',
  'song-break-p7',
  'song-break-p9',
};
const _added = {
  'song-break-d7',
  'song-break-d8',
  'song-break-d9',
  'song-break-p7',
  'song-break-p8',
  'song-break-p9',
};

MomentFacts _facts({
  bool weekly = true,
  bool refined = true,
  String? guest,
  int? previousRank = 124,
}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: weekly,
  refined: refined,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 87,
  previousRank: previousRank,
  featured: guest,
);

Map<String, String> _render(MomentFacts facts) => {
  for (final v in RefinedHeadlineCatalog.standard.of(_f05, facts))
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
  List<String> featuredOf(String songId) =>
      songId.endsWith('-f') ? const ['Guest Voice'] : const [];
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

ChartMomentEvent _arrival(ChartMomentScope scope, String id) {
  final key = '${scope.name}|arrival|$id';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: id,
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.firstThresholdEntry,
    entity: ChartEntitySnapshot(
      entityId: id,
      title: 'Paper Moon',
      artistId: 'mira',
      artistName: 'Mira Vale',
    ),
    weekStartUtc: DateTime.utc(2026, 10, 19),
    weekEndUtc: DateTime.utc(2026, 10, 26),
    occurredAt: DateTime.utc(2026, 10, 26, 12),
    createdAt: DateTime.utc(2026, 10, 26, 12),
    currentRank: 87,
    previousRank: 124,
    threshold: 100,
  );
}

void main() {
  group('SN-50 Batch 4: first Hot 100 entry from Bubbling Under', () {
    test('weekly lines render exactly as approved', () {
      final lines = _render(_facts());
      expect(
        lines['song-break-p3'],
        'Previously #124 on Sonus Bubbling Under, "Paper Moon" enters the '
        'Sonus Hot 100 at #87.',
      );
      expect(
        lines['song-break-d2'],
        '"Paper Moon" by Mira Vale enters the Sonus Hot 100 at #87, from #124 '
        'on Sonus Bubbling Under in the preceding chart week.',
      );
      expect(
        lines['song-break-d7'],
        '"Paper Moon" by Mira Vale enters the Sonus Hot 100 at #87; the week '
        'before, it was #124 on Sonus Bubbling Under.',
      );
      expect(
        lines['song-break-d8'],
        'After #124 on Sonus Bubbling Under, "Paper Moon" by Mira Vale makes '
        'its Sonus Hot 100 debut at #87.',
      );
      expect(
        lines['song-break-d9'],
        '"Paper Moon" by Mira Vale debuts on the Sonus Hot 100 at #87, having '
        'been #124 on Sonus Bubbling Under the week before.',
      );
      expect(
        lines['song-break-p7'],
        'New to the Sonus Hot 100: "Paper Moon" arrives at #87, after #124 on '
        'Sonus Bubbling Under the week before.',
      );
      expect(
        lines['song-break-p8'],
        'From #124 on Sonus Bubbling Under to a Sonus Hot 100 debut at #87: '
        '"Paper Moon" by Mira Vale is in.',
      );
      expect(
        lines['song-break-p9'],
        'Hot 100 debut! "Paper Moon" arrives on the Sonus Hot 100 at #87, '
        'having been #124 on Sonus Bubbling Under the week before.',
      );
    });

    test('a featured guest is credited wherever the artist is named', () {
      for (final MapEntry(key: id, value: text) in _render(
        _facts(guest: 'Guest Voice'),
      ).entries) {
        if (text.contains('"Paper Moon" by Mira Vale')) {
          expect(
            text,
            contains('"Paper Moon" by Mira Vale featuring Guest Voice'),
            reason: id,
          );
        }
      }
    });

    test('career stories never say "the week before" or "preceding chart '
        'week"', () {
      final lines = _render(_facts(weekly: false));
      expect(lines.keys.toSet().intersection(_weeklyOnly), isEmpty);
      expect(lines, contains('song-break-d8'));
      expect(lines, contains('song-break-p8'));
      expect(lines['song-break-p3'], startsWith('Previously #124 on Sonus'));
      for (final text in lines.values) {
        expect(text, isNot(contains('week before')));
        expect(text, isNot(contains('preceding')));
      }
    });

    test('without a Bubbling Under previous rank, no new line is offered', () {
      for (final previous in [null, 95]) {
        final ids = _render(_facts(previousRank: previous)).keys.toSet();
        expect(ids.intersection(_added), isEmpty, reason: '$previous');
        expect(ids, isNot(contains('song-break-p3')));
        expect(ids, isNot(contains('song-break-d2')));
      }
    });

    test('no refined F05 line tells a climb, a place count or an artist '
        'debut', () {
      for (final weekly in [true, false]) {
        for (final MapEntry(key: id, value: text) in _render(
          _facts(weekly: weekly),
        ).entries) {
          expect(text, isNot(contains('37')), reason: id);
          expect(text, isNot(contains('climbs')), reason: id);
          expect(text, isNot(contains('jumps')), reason: id);
          expect(text, isNot(startsWith('Mira Vale')), reason: id);
        }
      }
    });

    test('the legacy F05 catalog keeps its lines and words', () {
      final legacy = MomentHeadlines.legacyOf(_f05);
      expect({for (final v in legacy) v.id}.intersection(_added), isEmpty);
      final p3 = legacy.singleWhere((v) => v.id == 'song-break-p3');
      expect(
        p3.build(_facts(refined: false)),
        '"Paper Moon" jumps from #124 to #87, into the Sonus Hot 100.',
      );
    });

    test('composed refined arrivals pick only accurate lines', () {
      final desk = MomentEditorialDesk(
        lookups: const _Lookups(),
        rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
      );
      final picked = <String>{};
      for (final scope in [
        ChartMomentScope.finalized,
        ChartMomentScope.allTime,
      ]) {
        for (var i = 0; i < 60; i++) {
          for (final id in ['song-$i', 'song-$i-f']) {
            final story = desk
                .compose(
                  const ChartMomentFeedAggregator().aggregate([
                    _arrival(scope, id),
                  ]),
                )
                .single;
            expect(story.family, _f05);
            picked.add(story.variantId);
            expect(story.variantId, isNot('song-break-p4'));
            if (scope == ChartMomentScope.allTime) {
              expect(_weeklyOnly, isNot(contains(story.variantId)));
            }
            expect(story.headline, isNot(contains('37')));
            expect(story.headline, isNot(contains('climbs')));
          }
        }
      }
      // PulsePop tells refined arrivals; the new lines are reachable.
      expect(
        picked.intersection({
          'song-break-p7',
          'song-break-p8',
          'song-break-p9',
        }),
        isNotEmpty,
      );
    });
  });
}
