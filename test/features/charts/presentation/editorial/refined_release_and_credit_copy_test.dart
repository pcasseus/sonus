// SN-50 Batch 3 (contract §6.3 P-024 to P-050 with revised P-029; §6.5
// CJ-041; song-weeks-p5 and six chart-jump lines with full credits):
// refined-only wording. Stories under the earlier rules keep their words
// (pinned by legacy_rendering_golden_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

MomentFacts _facts(MomentFamily family, {bool refined = true, String? guest}) {
  final releaseFamily = family.isRelease;
  final rank = family.isNumberOne ? 1 : 7;
  return MomentFacts(
    chartType: releaseFamily ? ChartType.albums : ChartType.songs,
    weekly: false,
    refined: refined,
    title: 'Paper Moon',
    artist: 'Mira Vale',
    format: releaseFamily ? ReleaseFormat.ep : null,
    rank: rank,
    previousRank: rank + 23,
    previousPeak: rank + 2,
    streams: 57,
    milestone: 100,
    threshold: 10,
    weeks: 5,
    consecutive: true,
    rivalTitle: 'Glass Harbor',
    rivalArtist: 'Ilse Moor',
    featured: guest,
    jump: const ChartJumpFacts(fromRank: 47, toRank: 7, weeks: 3),
  );
}

MomentFamily _familyOf(String id) => MomentHeadlines.families.firstWhere(
  (family) => MomentHeadlines.legacyOf(family).any((v) => v.id == id),
);

String _refined(String id, {String? guest}) {
  final family = _familyOf(id);
  final facts = _facts(family, guest: guest);
  return RefinedHeadlineCatalog.standard
      .of(family, facts)
      .singleWhere((v) => v.id == id)
      .build(facts);
}

String _legacy(String id, {String? guest}) {
  final family = _familyOf(id);
  return MomentHeadlines.legacyOf(family)
      .singleWhere((v) => v.id == id)
      .build(_facts(family, refined: false, guest: guest));
}

void main() {
  group('SN-50 Batch 3: release wording and full credits', () {
    test('P-024 to P-050 render exactly as approved; legacy keeps its '
        'words', () {
      const expected = {
        'release-debut-1-d1':
            'Paper Moon by Mira Vale opens its chart run at #1 on the Sonus '
            'Albums & EPs chart.',
        'release-debut-1-d3':
            'The EP Paper Moon by Mira Vale debuts at #1 on the Sonus Albums & '
            'EPs chart with 57 streams.',
        'release-debut-d1':
            'The EP Paper Moon by Mira Vale debuts at #7 on the Sonus Albums & '
            'EPs chart.',
        'release-debut-d3':
            'The EP Paper Moon by Mira Vale opens at #7 with 57 streams.',
        'release-1-d1':
            'The EP Paper Moon by Mira Vale reaches #1 on the Sonus Albums & '
            'EPs chart.',
        'release-1-d2':
            'Paper Moon by Mira Vale succeeds Glass Harbor by Ilse Moor at #1 '
            'on the Sonus Albums & EPs chart, the new #1 EP.',
        'release-1-d3':
            'Paper Moon by Mira Vale rises from #24 to become the #1 EP on the '
            'Sonus Albums & EPs chart.',
        'release-1-d4':
            'Paper Moon by Mira Vale tops the Sonus Albums & EPs chart with 57 '
            'streams, the new #1 EP.',
        'release-1-again-d1':
            'The EP Paper Moon by Mira Vale returns to #1 on the Sonus Albums & '
            'EPs chart.',
        'release-1-again-d2':
            'Paper Moon by Mira Vale is the #1 EP again, taking over from Glass '
            'Harbor by Ilse Moor.',
        'release-1-again-p1':
            'Back at #1! The EP Paper Moon by Mira Vale reclaims the top spot.',
        'release-1-again-p5':
            "Once more at #1: Mira Vale's EP Paper Moon heads the Sonus Albums "
            '& EPs chart again.',
        'release-peak-d1':
            'The EP Paper Moon by Mira Vale reaches a new peak of #7 on the '
            'Sonus Albums & EPs chart.',
        'release-peak-d4':
            'The EP Paper Moon by Mira Vale enters the Top 10 at #7 on the '
            'Sonus Albums & EPs chart.',
        'release-peak-d5':
            'With 57 streams, the EP Paper Moon by Mira Vale hits a new peak of '
            '#7.',
        'release-peak-d6':
            'Paper Moon by Mira Vale moves from #30 to #7, a new peak for the '
            'EP.',
        'release-peak-p1':
            'New peak for the EP! Paper Moon by Mira Vale climbs to #7.',
        'release-peak-p5':
            '57 streams and a new peak: the EP Paper Moon by Mira Vale reaches '
            '#7.',
        'release-reentry-d1':
            'The EP Paper Moon by Mira Vale re-enters the Sonus Albums & EPs '
            'chart at #7.',
        'release-reentry-d2':
            'Back on the Sonus Albums & EPs chart: the EP Paper Moon by Mira '
            'Vale returns at #7.',
        'release-reentry-d4':
            'The EP Paper Moon by Mira Vale returns at #7, having peaked at #9.',
        'release-reentry-p1':
            'The EP is back! Paper Moon by Mira Vale re-enters at #7.',
        'release-streams-d1':
            'The EP Paper Moon by Mira Vale reaches 100 streams on Sonus.',
        'release-streams-d3':
            'The EP Paper Moon by Mira Vale reaches 100 streams and stands at #7 '
            'on the Sonus Albums & EPs chart.',
        'release-streams-d6':
            'The EP Paper Moon by Mira Vale passes 100 streams.',
        'release-streams-p1':
            '100 streams! The EP Paper Moon by Mira Vale hits a streaming '
            'milestone.',
        'release-streams-p5':
            'Milestone unlocked: the EP Paper Moon by Mira Vale reaches 100 '
            'streams.',
      };
      expect(expected, hasLength(27));
      for (final MapEntry(key: id, value: text) in expected.entries) {
        expect(_refined(id), text, reason: id);
        expect(_legacy(id), isNot(text), reason: '$id legacy is unchanged');
      }
    });

    test('song-weeks-p5 and the chart-jump lines credit every performer', () {
      const guest = 'Guest Voice';
      const credited = '"Paper Moon" by Mira Vale featuring Guest Voice';
      const expected = {
        'song-weeks-p5': '5 weeks in the Top 10 for $credited.',
        'song-jump-d4':
            '$credited rises 23 places to #7 on the weekly Sonus Hot 100.',
        'song-jump-d6':
            '$credited gains 23 places on the weekly Sonus Hot 100 and reaches '
            '#7.',
        'song-jump-p4': '$credited soars 23 places to #7 on the Sonus Hot 100.',
        'song-run-d3':
            '$credited is up 40 places over 3 weeks on the weekly Sonus Hot 100, '
            'now #7.',
        'song-run-d6':
            '$credited keeps climbing the weekly Sonus Hot 100 and reaches #7.',
        'song-run-p4': '$credited is on a run, up 40 spots in 3 weeks to #7.',
      };
      for (final MapEntry(key: id, value: text) in expected.entries) {
        expect(_refined(id, guest: guest), text, reason: id);
        // Without a guest the wording is the same, with the plain credit.
        expect(
          _refined(id),
          text.replaceAll(credited, '"Paper Moon" by Mira Vale'),
          reason: id,
        );
        // The legacy line still credits the primary artist only.
        expect(_legacy(id, guest: guest), isNot(contains(guest)), reason: id);
      }
    });

    test('the chart-jump families keep six distinct lines per publisher', () {
      for (final family in [
        MomentFamily.songHot100MajorJump,
        MomentFamily.songHot100ClimbRun,
      ]) {
        for (final guest in [null, 'Guest Voice']) {
          final facts = _facts(family, guest: guest);
          final variants = RefinedHeadlineCatalog.standard.of(family, facts);
          final texts = {for (final v in variants) v.build(facts)};
          expect(texts, hasLength(12), reason: family.name);
        }
      }
    });
  });
}
