// SN-50 Batch 8 (contract §6.2): artistRepeatNumberOne,
// artistRepeatNumberOneRelease and artistSimultaneousReleases, 6 Sonus
// Daily + 6 PulsePop lines each, approved. Ordinals count distinct #1 songs
// or releases, so no line counts weeks.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

MomentFacts _song() => MomentFacts(
  chartType: ChartType.songs,
  weekly: true,
  refined: true,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 1,
  ordinal: 2,
);

MomentFacts _release() => MomentFacts(
  chartType: ChartType.albums,
  weekly: true,
  refined: true,
  title: 'Night Signals',
  artist: 'Mira Vale',
  format: ReleaseFormat.album,
  rank: 1,
  ordinal: 2,
);

MomentFacts _roundup() => MomentFacts(
  chartType: ChartType.albums,
  weekly: true,
  refined: true,
  title: 'Mira Vale',
  artist: 'Mira Vale',
  rank: 2,
  threshold: 10,
  count: 3,
);

Map<String, String> _render(MomentFamily family, MomentFacts facts) => {
  for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
    if (v.fits(facts)) v.id: v.build(facts),
};

void main() {
  group('SN-50 Batch 8: repeat #1s and release roundups', () {
    test('artistRepeatNumberOne renders all twelve approved lines', () {
      expect(_render(MomentFamily.artistRepeatNumberOne, _song()), {
        'artist-repeat-1-d1':
            'Mira Vale earns a second #1 on the weekly Sonus Hot 100 as "Paper '
            'Moon" takes the top spot.',
        'artist-repeat-1-p1':
            "That's a second #1 song for Mira Vale: \"Paper Moon\" tops the "
            'weekly Sonus Hot 100!',
        'artist-repeat-1-d2':
            '"Paper Moon" takes #1 on the weekly Sonus Hot 100, a second #1 song '
            'there for Mira Vale.',
        'artist-repeat-1-d3':
            'Mira Vale collects a second #1 on the weekly Sonus Hot 100 with '
            '"Paper Moon".',
        'artist-repeat-1-d4':
            'With "Paper Moon" at the top, Mira Vale now has 2 #1 songs on the '
            'weekly Sonus Hot 100.',
        'artist-repeat-1-d5':
            "\"Paper Moon\" is Mira Vale's second #1 song on the weekly Sonus "
            'Hot 100.',
        'artist-repeat-1-d6':
            'The weekly Sonus Hot 100 has a new #1 in "Paper Moon", a second #1 '
            'song for Mira Vale.',
        'artist-repeat-1-p2':
            'Mira Vale is back on top with a second #1 song: "Paper Moon"!',
        'artist-repeat-1-p3':
            'Another one! "Paper Moon" gives Mira Vale a second #1 song.',
        'artist-repeat-1-p4':
            'Mira Vale does it again: "Paper Moon" hits #1 on the weekly Sonus '
            'Hot 100.',
        'artist-repeat-1-p5':
            "#1 again for Mira Vale! This time it's \"Paper Moon\", the artist's "
            'second #1 song.',
        'artist-repeat-1-p6':
            'Mira Vale adds another #1 song: "Paper Moon" takes the top spot!',
      });
    });

    test('artistRepeatNumberOneRelease renders all twelve approved lines', () {
      expect(_render(MomentFamily.artistRepeatNumberOneRelease, _release()), {
        'artist-release-repeat-1-d1':
            'Night Signals gives Mira Vale a second #1 on the weekly Sonus '
            'Albums & EPs chart.',
        'artist-release-repeat-1-p1':
            'Mira Vale collects a second #1 release with the album Night '
            'Signals!',
        'artist-release-repeat-1-d2':
            "The album Night Signals is Mira Vale's second release to reach #1 "
            'on the weekly Sonus Albums & EPs chart.',
        'artist-release-repeat-1-d3':
            'Mira Vale now counts 2 #1 releases on the weekly Sonus Albums & EPs '
            'chart, the latest being the album Night Signals.',
        'artist-release-repeat-1-d4':
            "Mira Vale's second #1 release on the weekly Sonus Albums & EPs "
            'chart is the album Night Signals.',
        'artist-release-repeat-1-d5':
            'Night Signals takes #1 on the weekly Sonus Albums & EPs chart, '
            "adding a second #1 release to Mira Vale's record.",
        'artist-release-repeat-1-d6':
            "The album Night Signals becomes Mira Vale's latest #1 release on "
            'the weekly Sonus Albums & EPs chart, the second in all.',
        'artist-release-repeat-1-p2':
            'Back at #1! Mira Vale returns to the top of the Sonus Albums & EPs '
            'chart with Night Signals.',
        'artist-release-repeat-1-p3':
            '#1 again! Night Signals hands Mira Vale a second chart-topping '
            'release.',
        'artist-release-repeat-1-p4':
            'Another #1 release for Mira Vale: the album Night Signals takes the '
            'top spot!',
        'artist-release-repeat-1-p5':
            'Night Signals makes it 2 #1 releases for Mira Vale!',
        'artist-release-repeat-1-p6':
            'Chart-topper number 2 for Mira Vale: the album Night Signals is #1!',
      });
    });

    test('artistSimultaneousReleases renders all twelve approved lines', () {
      expect(_render(MomentFamily.artistSimultaneousReleases, _roundup()), {
        'artist-sim-release-d1':
            'Mira Vale has 3 releases in the Top 10 of the weekly Sonus Albums '
            '& EPs chart at once.',
        'artist-sim-release-d2':
            '3 releases by Mira Vale sit in the Top 10 of the weekly Sonus '
            'Albums & EPs chart.',
        'artist-sim-release-p1':
            'Catalog power: Mira Vale has 3 releases in the Top 10.',
        'artist-sim-release-d3':
            'Mira Vale holds 3 places in the Top 10 of the weekly Sonus Albums '
            '& EPs chart.',
        'artist-sim-release-d4':
            '3 of the Top 10 releases on the weekly Sonus Albums & EPs chart are '
            'by Mira Vale.',
        'artist-sim-release-d5':
            'Mira Vale places 3 releases in the Top 10 of the weekly Sonus '
            'Albums & EPs chart.',
        'artist-sim-release-d6':
            'Mira Vale appears 3 times in the Top 10 of the weekly Sonus Albums '
            '& EPs chart.',
        'artist-sim-release-p2': '3 at once! Mira Vale crowds the Top 10.',
        'artist-sim-release-p3':
            'Mira Vale is everywhere: 3 releases in the Top 10!',
        'artist-sim-release-p4': 'Top 10 takeover: 3 releases from Mira Vale.',
        'artist-sim-release-p5':
            'Mira Vale stacks the Top 10 with 3 releases at the same time.',
        'artist-sim-release-p6':
            'Mira Vale fills 3 Top 10 slots on the weekly Sonus Albums & EPs '
            'chart at once!',
      });
    });

    test('no repeat-#1 line counts weeks', () {
      for (final (family, facts) in [
        (MomentFamily.artistRepeatNumberOne, _song()),
        (MomentFamily.artistRepeatNumberOneRelease, _release()),
      ]) {
        for (final MapEntry(key: id, value: text) in _render(
          family,
          facts,
        ).entries) {
          expect(text, isNot(contains('weekly #1s')), reason: id);
          expect(text, isNot(contains('weeks')), reason: id);
        }
      }
    });

    test('all three families are approved', () {
      expect(
        MomentHeadlines.approvedFamilies,
        containsAll([
          MomentFamily.artistRepeatNumberOne,
          MomentFamily.artistRepeatNumberOneRelease,
          MomentFamily.artistSimultaneousReleases,
        ]),
      );
    });
  });
}
