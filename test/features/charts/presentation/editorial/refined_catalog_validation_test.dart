// SN-50 editorial contract §4 and §8 item 5: a family is selectable under
// the refined rules only with 6 distinct Sonus Daily and 6 distinct
// PulsePop lines that pass the copy rules. This checks every approved
// family's refined lines, so a family approved later is covered too.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// Families told only about a finished week.
const _weeklyOnly = {
  MomentFamily.songBubblingUnderFall,
  MomentFamily.songHot100Exit,
  // App Update 1.2 (REF-19): finalized weekly charts only.
  MomentFamily.artistChartSweep,
  MomentFamily.artistTop10Presence,
  MomentFamily.artistHot100Presence,
  MomentFamily.artistJointControl,
};

/// REF-19 facts large enough for every line, Pulse Pop minimums included:
/// a Top 10 sweep, 6 Top 10 songs, 17 Hot 100 songs.
(ArtistDominance, int threshold, int count)? _dominance(MomentFamily family) =>
    switch (family) {
      MomentFamily.artistChartSweep => (
        const ArtistDominance(ArtistDominanceKind.sweep, 10),
        10,
        10,
      ),
      MomentFamily.artistTop10Presence => (
        const ArtistDominance(ArtistDominanceKind.top10, 5),
        10,
        6,
      ),
      MomentFamily.artistHot100Presence => (
        const ArtistDominance(ArtistDominanceKind.hot100, 15),
        100,
        17,
      ),
      _ => null,
    };

/// Joint control facts large enough for every line: a Top 6 held 4–2.
bool _isJoint(MomentFamily family) => family == MomentFamily.artistJointControl;

MomentFacts _facts(MomentFamily family, {required bool weekly}) {
  final releaseFamily = family.isRelease;
  final numberOne =
      family.isNumberOne || family == MomentFamily.artistTopArtist;
  final (rank, previousRank, previousPeak) = switch (family) {
    _ when numberOne => (1, 4, 2),
    MomentFamily.songBubblingUnderDebut => (106, null, null),
    MomentFamily.songHot100Breakthrough => (94, 106, 106),
    MomentFamily.songBubblingUnderFall => (168, 122, 110),
    MomentFamily.songHot100Exit => (121, 94, 35),
    _ => (7, 30, 9),
  };
  final dominance = _dominance(family);
  return MomentFacts(
    chartType: releaseFamily ? ChartType.albums : ChartType.songs,
    weekly: weekly,
    refined: true,
    title: 'Paper Moon',
    artist: 'Mira Vale',
    ownerName: 'Mira Vale & Co',
    album: 'Night Signals',
    format: releaseFamily ? ReleaseFormat.ep : null,
    rank: rank,
    previousRank: previousRank,
    previousPeak: previousPeak,
    streams: 57,
    milestone: 100,
    ordinal: 3,
    threshold: _isJoint(family) ? 6 : dominance?.$2 ?? 10,
    weeks: 5,
    rivalTitle: 'Glass Harbor',
    rivalArtist: 'Ilse Moor',
    consecutive: true,
    count: _isJoint(family) ? 4 : dominance?.$3 ?? 3,
    dominance: dominance?.$1,
    jointPartner: _isJoint(family) ? 'Juno Hart' : null,
    thresholds: const [75, 50, 40],
    jump: rank == 7
        ? const ChartJumpFacts(
            fromRank: 47,
            toRank: 7,
            weeks: 3,
            weekStreams: 245,
            previousWeekStreams: 235,
          )
        : null,
  );
}

void main() {
  test('every approved family has 6 + 6 distinct refined lines that pass '
      'the copy rules', () {
    const banned = [
      'lifetime',
      'summit',
      'all-time',
      'another chart cycle',
      'steady movement',
      'points',
      'this week',
      'last week',
      'this stream',
      'for now',
      'null',
    ];
    // Every catalog version this build carries (SN-50 R-V).
    for (final catalog in RefinedHeadlineCatalog.versions.values) {
      for (final family in MomentHeadlines.approvedFamilies) {
        // Device-polish families are told only outside the refined rules.
        if (family == MomentFamily.releaseClimb) continue;
        for (final weekly in [true, if (!_weeklyOnly.contains(family)) false]) {
          final facts = _facts(family, weekly: weekly);
          final lines = [
            for (final v in catalog.of(family, facts))
              if (v.fits(facts)) v,
          ];
          for (final publisher in MomentPublisher.values) {
            final texts = {
              for (final v in lines)
                if (v.publisher == publisher) v.build(facts),
            };
            expect(
              texts.length,
              greaterThanOrEqualTo(6),
              reason: '${family.name} weekly:$weekly ${publisher.name}',
            );
          }
          final ids = <String>{};
          for (final v in lines) {
            expect(ids.add(v.id), isTrue, reason: 'duplicate ${v.id}');
            final text = v.build(facts);
            for (final word in banned) {
              expect(text.toLowerCase(), isNot(contains(word)), reason: v.id);
            }
            expect(text, isNot(contains('  ')), reason: v.id);
            expect(text, matches(RegExp(r'[.!]$')), reason: v.id);
            if (family.isNumberOne) {
              expect(text, contains('#1'), reason: v.id);
            }
          }
        }
      }
    }
  });

  test('refined line ids never repeat across families', () {
    final seen = <String, MomentFamily>{};
    for (final family in MomentFamily.values) {
      final facts = _facts(family, weekly: true);
      for (final v in RefinedHeadlineCatalog.standard.of(family, facts)) {
        final other = seen[v.id];
        expect(other, anyOf(isNull, family), reason: v.id);
        seen[v.id] = family;
      }
    }
  });
}
