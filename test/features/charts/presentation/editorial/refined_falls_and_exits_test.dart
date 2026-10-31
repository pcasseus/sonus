// SN-50 Batch 5 (contract §6.1 D and E; BUG-04 approved rules 2 and 3):
// Bubbling Under falls of 30+ and notable Hot 100 exits, refined rules
// only, under their held ids (#bu-fall, #hot-100-exit).
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

const _fall = MomentFamily.songBubblingUnderFall;
const _exit = MomentFamily.songHot100Exit;
const _peakLines = {'song-exit-d3', 'song-exit-d4', 'song-exit-p3'};

MomentFacts _facts({
  required int rank,
  required int? previousRank,
  int? previousPeak,
  bool weekly = true,
  String? guest,
}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: weekly,
  refined: true,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: rank,
  previousRank: previousRank,
  previousPeak: previousPeak,
  featured: guest,
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

ChartMomentEvent _event(
  ChartMomentEventType type,
  String id, {
  ChartMomentScope scope = ChartMomentScope.finalized,
  int? rank,
  int? previousRank,
  int? previousPeak,
  int? threshold,
}) {
  final key = '${scope.name}|${type.name}|$id';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: id,
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: ChartEntitySnapshot(
      entityId: id,
      title: 'Paper Moon $id',
      artistId: 'mira',
      artistName: 'Mira Vale',
    ),
    weekStartUtc: DateTime.utc(2026, 10, 19),
    weekEndUtc: DateTime.utc(2026, 10, 26),
    occurredAt: DateTime.utc(2026, 10, 26, 12),
    createdAt: DateTime.utc(2026, 10, 26, 12),
    currentRank: rank,
    previousRank: previousRank,
    previousPeakRank: previousPeak,
    threshold: threshold,
  );
}

ChartMomentEvent _fallEvent(
  String id, {
  int from = 122,
  int to = 168,
  ChartMomentScope scope = ChartMomentScope.finalized,
}) => _event(
  ChartMomentEventType.rankFall,
  id,
  scope: scope,
  rank: to,
  previousRank: from,
);

ChartMomentEvent _exitEvent(String id, {int? peak = 35}) => _event(
  ChartMomentEventType.thresholdExit,
  id,
  rank: 121,
  previousRank: 94,
  previousPeak: peak,
  threshold: 100,
);

List<MomentStory> _compose(List<ChartMomentEvent> events, {int minor = 3}) =>
    MomentEditorialDesk(
      lookups: const _Lookups(),
      rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
      minorStoriesPerDay: minor,
    ).compose(const ChartMomentFeedAggregator().aggregate(events));

void main() {
  group('SN-50 Batch 5: Bubbling Under falls (BU-020 to BU-031)', () {
    test('every line renders exactly as approved', () {
      expect(_render(_fall, _facts(rank: 168, previousRank: 122)), {
        'song-bu-fall-d1':
            '"Paper Moon" by Mira Vale falls from #122 to #168 on the weekly '
            'Sonus Bubbling Under.',
        'song-bu-fall-d2':
            '"Paper Moon" by Mira Vale drops 46 places on the weekly Sonus '
            'Bubbling Under, to #168.',
        'song-bu-fall-d3':
            '"Paper Moon" by Mira Vale slips to #168 on the weekly Sonus '
            'Bubbling Under, down from #122.',
        'song-bu-fall-d4':
            'A 46-place fall on the weekly Sonus Bubbling Under takes "Paper '
            'Moon" by Mira Vale to #168.',
        'song-bu-fall-d5':
            '"Paper Moon" by Mira Vale moves down the weekly Sonus Bubbling '
            'Under, from #122 to #168.',
        'song-bu-fall-d6':
            '"Paper Moon" by Mira Vale loses 46 places on the weekly Sonus '
            'Bubbling Under and sits at #168.',
        'song-bu-fall-p1':
            'Down 46: "Paper Moon" slides to #168 on Sonus Bubbling Under.',
        'song-bu-fall-p2':
            '"Paper Moon" takes a tumble on Sonus Bubbling Under, from #122 to '
            '#168.',
        'song-bu-fall-p3':
            'Rough week for "Paper Moon" by Mira Vale: down to #168 on Sonus '
            'Bubbling Under.',
        'song-bu-fall-p4':
            '"Paper Moon" drops 46 spots to #168 on Sonus Bubbling Under.',
        'song-bu-fall-p5':
            'From #122 to #168: "Paper Moon" loses ground on Sonus Bubbling '
            'Under.',
        'song-bu-fall-p6':
            '"Paper Moon" by Mira Vale slips 46 places on Sonus Bubbling Under, '
            'now at #168.',
      });
    });

    test('placesDown comes only from a weekly previous rank', () {
      expect(_facts(rank: 168, previousRank: 122).placesDown, 46);
      expect(_facts(rank: 168, previousRank: null).placesDown, isNull);
      expect(
        _facts(rank: 168, previousRank: 122, weekly: false).placesDown,
        isNull,
      );
      expect(_facts(rank: 122, previousRank: 168).placesDown, isNull);
    });

    test('a fall of 30+ within Bubbling Under is a story under #bu-fall; '
        '-29, a missing link, a career chart or a boundary crossing is '
        'not', () {
      final told = _compose([_fallEvent('a')]);
      expect(told.single.family, _fall);
      expect(told.single.id, endsWith('#bu-fall'));
      expect(told.single.publisher, MomentPublisher.sonusDaily);
      expect(told.single.status, 'FALL');

      expect(_compose([_fallEvent('b', from: 122, to: 151)]), isEmpty);
      expect(
        _compose([_event(ChartMomentEventType.rankFall, 'c', rank: 168)]),
        isEmpty,
      );
      expect(
        _compose([
          _fallEvent('d', scope: ChartMomentScope.allTime),
        ]).where((s) => s.family == _fall),
        isEmpty,
      );
      expect(_compose([_fallEvent('e', from: 80, to: 130)]), isEmpty);
    });

    test('falls are minor stories, capped per day', () {
      final told = _compose([
        for (final id in ['a', 'b', 'c', 'd', 'e']) _fallEvent(id),
      ], minor: 3);
      expect(told.where((s) => s.family == _fall), hasLength(3));
      expect(_fall.tierFor(168).name, 'minor');
    });

    test('a featured guest is credited wherever the artist is named', () {
      for (final MapEntry(key: id, value: text) in _render(
        _fall,
        _facts(rank: 168, previousRank: 122, guest: 'Guest Voice'),
      ).entries) {
        if (text.contains('by Mira Vale')) {
          expect(
            text,
            contains('by Mira Vale featuring Guest Voice'),
            reason: id,
          );
        }
      }
    });
  });

  group('SN-50 Batch 5: notable Hot 100 exits (BU-040 to BU-051)', () {
    test('every line renders exactly as approved', () {
      expect(_render(_exit, _facts(rank: 121, previousRank: 94, previousPeak: 35)), {
        'song-exit-d1':
            '"Paper Moon" by Mira Vale leaves the Sonus Hot 100 and is #121 on '
            'the weekly Sonus Bubbling Under.',
        'song-exit-d2':
            '"Paper Moon" by Mira Vale slips from #94 on the Sonus Hot 100 to '
            '#121 on Sonus Bubbling Under.',
        'song-exit-d3':
            'Once #35 on the Sonus Hot 100, "Paper Moon" by Mira Vale moves to '
            'Sonus Bubbling Under at #121.',
        'song-exit-d4':
            '"Paper Moon" by Mira Vale exits the Sonus Hot 100 after peaking at '
            '#35; it is now #121 on Sonus Bubbling Under.',
        'song-exit-d5':
            'After its Sonus Hot 100 run, "Paper Moon" by Mira Vale continues on '
            'Sonus Bubbling Under at #121.',
        'song-exit-d6':
            '"Paper Moon" by Mira Vale drops out of the Sonus Hot 100, to #121 '
            'on Sonus Bubbling Under.',
        'song-exit-p1':
            'Out of the Sonus Hot 100: "Paper Moon" drops to #121 on Sonus '
            'Bubbling Under.',
        'song-exit-p2':
            '"Paper Moon" says goodbye to the Sonus Hot 100 and lands at #121 on '
            'Sonus Bubbling Under.',
        'song-exit-p3':
            'A #35 peak behind it, "Paper Moon" by Mira Vale slides to Sonus '
            'Bubbling Under at #121.',
        'song-exit-p4':
            '"Paper Moon" falls from #94 on the Sonus Hot 100 to #121 on Sonus '
            'Bubbling Under.',
        'song-exit-p5':
            'Hot 100 exit: "Paper Moon" by Mira Vale is now #121 on Sonus '
            'Bubbling Under.',
        'song-exit-p6':
            'A Sonus Hot 100 run comes to an end: "Paper Moon" is now #121 on '
            'Sonus Bubbling Under.',
      });
    });

    test('a peak is named only when it is a verified Top 40 peak', () {
      for (final peak in [null, 41, 60]) {
        final ids = _render(
          _exit,
          _facts(rank: 121, previousRank: 94, previousPeak: peak),
        ).keys.toSet();
        expect(ids.intersection(_peakLines), isEmpty, reason: '$peak');
        expect(ids, hasLength(9));
      }
    });

    test('ranks are positions on two charts, never a place count', () {
      for (final text in _render(
        _exit,
        _facts(rank: 121, previousRank: 94, previousPeak: 35),
      ).values) {
        expect(text, isNot(contains('27')));
        expect(text, isNot(contains('places')));
        expect(text, isNot(contains('for now')));
        expect(text, contains('Sonus Bubbling Under'));
      }
    });

    test('an exit after a Top 40 peak is told under #hot-100-exit and never '
        'capped; without a notable history there is no story', () {
      final told = _compose([
        for (final id in ['a', 'b', 'c', 'd', 'e']) _exitEvent(id),
      ], minor: 1);
      expect(told.where((s) => s.family == _exit), hasLength(5));
      expect(told.every((s) => s.id.endsWith('#hot-100-exit')), isTrue);
      expect(told.first.status, 'HOT 100 EXIT');
      expect(told.first.publisher, MomentPublisher.sonusDaily);

      expect(
        _compose([
          _exitEvent('quiet', peak: 60),
        ]).where((s) => s.family == _exit),
        isEmpty,
      );
    });

    test('a featured guest is credited wherever the artist is named', () {
      for (final MapEntry(key: id, value: text) in _render(
        _exit,
        _facts(
          rank: 121,
          previousRank: 94,
          previousPeak: 35,
          guest: 'Guest Voice',
        ),
      ).entries) {
        if (text.contains('by Mira Vale')) {
          expect(
            text,
            contains('by Mira Vale featuring Guest Voice'),
            reason: id,
          );
        }
      }
    });

    test('both families have no catalog lines and are approved', () {
      for (final family in [_fall, _exit]) {
        expect(MomentHeadlines.legacyOf(family), isEmpty);
        expect(MomentHeadlines.approvedFamilies, contains(family));
      }
    });
  });
}
