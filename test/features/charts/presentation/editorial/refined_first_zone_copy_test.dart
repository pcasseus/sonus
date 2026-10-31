// SN-50 Batch 6 (contract §6.2): songFirstThreshold and
// releaseFirstThreshold, 6 Sonus Daily + 6 PulsePop lines each, approved.
// The first entry belongs to the song or release; movement wording needs a
// real climb.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

MomentFacts _song({int? previousRank = 52, bool refined = true}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: true,
  refined: refined,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 38,
  previousRank: previousRank,
  threshold: 40,
);

MomentFacts _release({int? previousRank = 25}) => MomentFacts(
  chartType: ChartType.albums,
  weekly: true,
  refined: true,
  title: 'Night Signals',
  artist: 'Mira Vale',
  format: ReleaseFormat.album,
  rank: 18,
  previousRank: previousRank,
  threshold: 20,
);

Map<String, String> _render(MomentFamily family, MomentFacts facts) => {
  for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
    if (v.fits(facts)) v.id: v.build(facts),
};

void main() {
  group('SN-50 Batch 6: first-zone families', () {
    test('songFirstThreshold renders all twelve approved lines', () {
      expect(_render(MomentFamily.songFirstThreshold, _song()), {
        'song-zone-d1':
            '"Paper Moon" by Mira Vale enters the Top 40 of the weekly Sonus '
            'Hot 100 for the first time, at #38.',
        'song-zone-d2':
            'First time in the Top 40 of the weekly Sonus Hot 100: "Paper '
            'Moon" by Mira Vale is at #38.',
        'song-zone-p1':
            'Into the Top 40! "Paper Moon" by Mira Vale gets there for the '
            'first time, at #38.',
        'song-zone-p2':
            '"Paper Moon" cracks the Top 40 for the first time, at #38.',
        'song-zone-d3':
            '"Paper Moon" by Mira Vale reaches #38 on the weekly Sonus Hot 100, '
            'its first time in the Top 40.',
        'song-zone-d4':
            'A first Top 40 position for "Paper Moon" by Mira Vale: #38 on the '
            'weekly Sonus Hot 100.',
        'song-zone-d5':
            '"Paper Moon" by Mira Vale moves into the Top 40 of the weekly '
            'Sonus Hot 100 at #38, a first for the song.',
        'song-zone-d6':
            'At #38, "Paper Moon" by Mira Vale is inside the Top 40 of the '
            'weekly Sonus Hot 100 for the first time.',
        'song-zone-p3': 'Hello, Top 40! "Paper Moon" makes it in at #38.',
        'song-zone-p4':
            '"Paper Moon" breaks new ground at #38: a first Top 40 spot.',
        'song-zone-p5':
            'New territory for "Paper Moon": #38 and a place in the Top 40.',
        'song-zone-p6':
            'Top 40, unlocked: "Paper Moon" by Mira Vale lands at #38.',
      });
    });

    test('releaseFirstThreshold renders all twelve approved lines', () {
      expect(_render(MomentFamily.releaseFirstThreshold, _release()), {
        'release-zone-d1':
            'The album Night Signals by Mira Vale reaches the Top 20 of the '
            'weekly Sonus Albums & EPs chart for the first time, at #18.',
        'release-zone-p1':
            'Night Signals reaches the Top 20 for the first time, at #18!',
        'release-zone-d2':
            'Night Signals by Mira Vale earns its first Top 20 position, at #18 '
            'on the weekly Sonus Albums & EPs chart.',
        'release-zone-d3':
            'Night Signals by Mira Vale is now a Top 20 album: it reaches #18 on '
            'the weekly Sonus Albums & EPs chart, a first.',
        'release-zone-d4':
            'Night Signals by Mira Vale moves into the Top 20 of the weekly '
            "Sonus Albums & EPs chart at #18, the album's first time there.",
        'release-zone-d5':
            'At #18, the album Night Signals by Mira Vale enters the Top 20 of '
            'the weekly Sonus Albums & EPs chart for the first time.',
        'release-zone-d6':
            'For the album Night Signals by Mira Vale, #18 on the weekly Sonus '
            'Albums & EPs chart means a first Top 20 placing.',
        'release-zone-p2':
            'Top 20 for the album! Night Signals by Mira Vale arrives at #18.',
        'release-zone-p3':
            'Night Signals breaks into the Top 20 at #18, a first for the album.',
        'release-zone-p4':
            'New high-water mark: the album Night Signals enters the Top 20 at '
            '#18.',
        'release-zone-p5':
            "Mira Vale's album Night Signals makes the Top 20 for the first "
            'time, at #18!',
        'release-zone-p6':
            'First Top 20 spot for Night Signals: the album lands at #18.',
      });
    });

    test('without a climb, no line says "moves into", and both publishers '
        'still have lines', () {
      for (final (family, facts, moving) in [
        (
          MomentFamily.songFirstThreshold,
          _song(previousRank: null),
          'song-zone-d5',
        ),
        (
          MomentFamily.releaseFirstThreshold,
          _release(previousRank: null),
          'release-zone-d4',
        ),
      ]) {
        final lines = [
          for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
            if (v.fits(facts)) v,
        ];
        expect([for (final v in lines) v.id], isNot(contains(moving)));
        for (final publisher in MomentPublisher.values) {
          expect(lines.where((v) => v.publisher == publisher), isNotEmpty);
        }
        for (final v in lines) {
          expect(v.build(facts), isNot(contains('moves')), reason: v.id);
        }
      }
    });

    test('no line makes the zone an artist milestone', () {
      for (final MapEntry(key: id, value: text) in _render(
        MomentFamily.songFirstThreshold,
        _song(),
      ).entries) {
        expect(text, isNot(startsWith('Mira Vale')), reason: id);
      }
      for (final MapEntry(key: id, value: text) in _render(
        MomentFamily.releaseFirstThreshold,
        _release(),
      ).entries) {
        expect(text, isNot(startsWith('Mira Vale ')), reason: id);
      }
    });

    test('both families are approved; the catalog drafts keep their '
        'words', () {
      expect(
        MomentHeadlines.approvedFamilies,
        contains(MomentFamily.songFirstThreshold),
      );
      expect(
        MomentHeadlines.approvedFamilies,
        contains(MomentFamily.releaseFirstThreshold),
      );
      final legacy = MomentHeadlines.legacyOf(MomentFamily.songFirstThreshold);
      expect(
        [for (final v in legacy) v.id],
        ['song-zone-d1', 'song-zone-d2', 'song-zone-p1', 'song-zone-p2'],
      );
      expect(
        legacy
            .singleWhere((v) => v.id == 'song-zone-p2')
            .build(_song(refined: false)),
        'Mira Vale cracks the Top 40: "Paper Moon" reaches #38.',
      );
    });
  });
}
