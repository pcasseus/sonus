// SN-50 Batch 7 (contract §6.2): songSelfReplacement and
// releaseSelfReplacement, 6 Sonus Daily + 6 PulsePop lines each, approved.
// No line claims consecutive weekly #1s on career standings, and the
// replaced release is never given a format.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

MomentFacts _song({required bool weekly}) => MomentFacts(
  chartType: ChartType.songs,
  weekly: weekly,
  refined: true,
  title: 'Paper Moon',
  artist: 'Mira Vale',
  rank: 1,
  previousRank: 2,
  rivalTitle: 'Glass Harbor',
  rivalArtist: 'Mira Vale',
);

MomentFacts _release({required bool weekly}) => MomentFacts(
  chartType: ChartType.albums,
  weekly: weekly,
  refined: true,
  title: 'Night Signals',
  artist: 'Mira Vale',
  format: ReleaseFormat.album,
  rank: 1,
  previousRank: 3,
  rivalTitle: 'Low Tide',
  rivalArtist: 'Mira Vale',
);

Map<String, String> _render(MomentFamily family, MomentFacts facts) => {
  for (final v in RefinedHeadlineCatalog.standard.of(family, facts))
    if (v.fits(facts)) v.id: v.build(facts),
};

void main() {
  group('SN-50 Batch 7: self-replacement at #1', () {
    test('songSelfReplacement renders all twelve approved lines', () {
      expect(_render(MomentFamily.songSelfReplacement, _song(weekly: true)), {
        'song-self-1-d1':
            'Mira Vale replaces "Glass Harbor" with "Paper Moon" at #1 on the '
            'weekly Sonus Hot 100.',
        'song-self-1-d2':
            '"Paper Moon" takes over #1 on the weekly Sonus Hot 100 from "Glass '
            'Harbor", keeping the top spot with Mira Vale.',
        'song-self-1-p1':
            'Out with "Glass Harbor", in with "Paper Moon": Mira Vale stays at '
            '#1.',
        'song-self-1-p2':
            'Mira Vale follows one #1 with another: "Paper Moon" replaces '
            '"Glass Harbor".',
        'song-self-1-d3':
            'Mira Vale holds #1 on the weekly Sonus Hot 100 as "Paper Moon" '
            'succeeds "Glass Harbor".',
        'song-self-1-d4':
            '"Paper Moon" replaces "Glass Harbor" at #1 on the weekly Sonus Hot '
            '100; both songs are by Mira Vale.',
        'song-self-1-d5':
            'Mira Vale has a new #1 on the weekly Sonus Hot 100: "Paper Moon" '
            'takes over from "Glass Harbor".',
        'song-self-1-d6':
            '#1 on the weekly Sonus Hot 100 stays with Mira Vale, as "Paper '
            'Moon" replaces "Glass Harbor".',
        'song-self-1-p3':
            '#1 swap, same artist: "Paper Moon" takes over from "Glass Harbor" '
            'for Mira Vale.',
        'song-self-1-p4':
            '"Paper Moon" bumps "Glass Harbor" from #1, and Mira Vale keeps the '
            'top spot!',
        'song-self-1-p5':
            'Still #1, new song: Mira Vale trades "Glass Harbor" for "Paper '
            'Moon" at the top.',
        'song-self-1-p6':
            'One Mira Vale #1 makes way for another: "Paper Moon" succeeds '
            '"Glass Harbor".',
      });
    });

    test('releaseSelfReplacement renders all twelve approved lines', () {
      expect(_render(MomentFamily.releaseSelfReplacement, _release(weekly: true)), {
        'release-self-1-d1':
            'Mira Vale replaces Low Tide with the album Night Signals at #1 '
            'on the weekly Sonus Albums & EPs chart.',
        'release-self-1-p1':
            'Mira Vale follows one #1 release with another: the album Night '
            'Signals replaces Low Tide.',
        'release-self-1-d2':
            'The album Night Signals succeeds Low Tide at #1 on the weekly '
            'Sonus Albums & EPs chart, keeping the top spot with Mira Vale.',
        'release-self-1-d3':
            'The top of the weekly Sonus Albums & EPs chart changes hands '
            "within Mira Vale's catalog: Night Signals is the new #1.",
        'release-self-1-d4':
            'On the weekly Sonus Albums & EPs chart, Night Signals takes over '
            'at #1 from Low Tide, another release by Mira Vale.',
        'release-self-1-d5':
            "Night Signals is Mira Vale's new #1 album on the weekly Sonus "
            'Albums & EPs chart, replacing Low Tide.',
        'release-self-1-d6':
            'With the album Night Signals, Mira Vale follows Low Tide at #1 on '
            'the weekly Sonus Albums & EPs chart.',
        'release-self-1-p2':
            'New album, same #1 artist: Night Signals replaces Low Tide for '
            'Mira Vale!',
        'release-self-1-p3':
            "Night Signals unseats Low Tide at #1, and the top spot stays in "
            "Mira Vale's hands!",
        'release-self-1-p4':
            'Catalog takeover: Mira Vale swaps one #1 for another with the '
            'album Night Signals.',
        'release-self-1-p5':
            'Mira Vale still rules #1! The album Night Signals replaces Low '
            'Tide.',
        'release-self-1-p6':
            "The #1 album is new, the artist isn't: Night Signals by Mira Vale "
            'replaces Low Tide.',
      });
    });

    test('career stories claim no consecutive weekly #1s and name the plain '
        'chart', () {
      for (final (family, facts) in [
        (MomentFamily.songSelfReplacement, _song(weekly: false)),
        (MomentFamily.releaseSelfReplacement, _release(weekly: false)),
      ]) {
        final lines = _render(family, facts);
        expect(lines, hasLength(12), reason: family.name);
        for (final MapEntry(key: id, value: text) in lines.entries) {
          expect(
            text.toLowerCase(),
            isNot(contains('back-to-back')),
            reason: id,
          );
          expect(text, isNot(contains('in a row')), reason: id);
          expect(text, isNot(contains('weekly')), reason: id);
          expect(text, contains('#1'), reason: id);
        }
      }
    });

    test('the replaced release is never given a format', () {
      for (final weekly in [true, false]) {
        for (final text in _render(
          MomentFamily.releaseSelfReplacement,
          _release(weekly: weekly),
        ).values) {
          expect(text, isNot(contains('album Low Tide')));
          expect(text, isNot(contains('EP Low Tide')));
        }
      }
    });

    test('both families are approved', () {
      expect(
        MomentHeadlines.approvedFamilies,
        containsAll([
          MomentFamily.songSelfReplacement,
          MomentFamily.releaseSelfReplacement,
        ]),
      );
    });
  });
}
