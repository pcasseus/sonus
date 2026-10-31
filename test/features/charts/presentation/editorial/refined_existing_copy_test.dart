// SN-50 Batch 2 (contract §6.3 P-001, P-002, P-010 to P-023; §6.4; P-051):
// refined-only corrections to the approved catalog. Stories under the
// earlier rules keep their words (pinned by legacy_rendering_golden_test).
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

const _guestLines = {
  'song-debut-1-p4',
  'song-debut-10-p6',
  'song-debut-p2',
  'song-bu-debut-p2',
  'song-bu-debut-p5',
  'song-break-d5',
  'song-peak-p2',
  'song-repeak-d5',
  'song-climb-d5',
  'song-gainer-d5',
  'song-reentry-d5',
  'song-streams-d4',
  'song-streams-p6',
  'artist-top10-d5',
};

/// Chart-jump families: approved separately (CJ-001 to CJ-041) and not part
/// of this batch's attribution exclusions.
const _chartJumps = {
  MomentFamily.songHot100MajorJump,
  MomentFamily.songHot100ClimbRun,
};

MomentFacts _facts(
  MomentFamily family, {
  bool refined = true,
  bool weekly = false,
  String? guest,
  bool previousRank = true,
  bool previousPeak = true,
  bool streams = true,
  bool owner = true,
  bool rival = true,
  bool ordinal = true,
  bool weeks = true,
  bool count = true,
}) {
  final releaseFamily = family.isRelease;
  final numberOne =
      family.isNumberOne || family == MomentFamily.artistTopArtist;
  final rank = switch (family) {
    _ when numberOne => 1,
    MomentFamily.songBubblingUnderDebut => 106,
    MomentFamily.songHot100Breakthrough => 94,
    _ => 7,
  };
  return MomentFacts(
    chartType: releaseFamily ? ChartType.albums : ChartType.songs,
    weekly: weekly,
    refined: refined,
    title: 'Paper Moon',
    artist: 'Mira Vale',
    ownerName: owner ? 'Mira Vale & Co' : null,
    album: 'Night Signals',
    format: releaseFamily ? ReleaseFormat.ep : null,
    rank: rank,
    previousRank: !previousRank
        ? null
        : family == MomentFamily.songHot100Breakthrough
        ? 106
        : rank + 23,
    previousPeak: previousPeak ? rank + 2 : null,
    streams: streams ? 57 : null,
    milestone: 100,
    ordinal: ordinal ? 3 : null,
    threshold: 10,
    weeks: weeks ? 5 : null,
    rivalTitle: rival ? 'Glass Harbor' : null,
    rivalArtist: rival ? 'Ilse Moor' : null,
    featured: guest,
    consecutive: weeks,
    count: count ? 3 : null,
    thresholds: const [75, 50, 40],
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

String _legacy(String id) {
  final family = _familyOf(id);
  return MomentHeadlines.legacyOf(
    family,
  ).singleWhere((v) => v.id == id).build(_facts(family, refined: false));
}

List<String> _refinedIds(MomentFamily family, MomentFacts facts) => [
  for (final v in RefinedHeadlineCatalog.standard.of(family, facts)) v.id,
];

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Artist $artistId';
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> featuredOf(String songId) => const ['Guest Voice'];
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
  ChartMomentScope scope,
  String source, {
  int? rank,
  int? previousRank,
  int? previousPeak,
  int? threshold,
  int? streams,
  int? milestone,
}) {
  final song = ChartEntitySnapshot(
    entityId: 'song-${type.name}-$source',
    title: 'Paper Moon $source',
    artistId: 'mira',
    artistName: 'Mira Vale',
  );
  final key = '${scope.name}|${type.name}|$source';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source,
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: song,
    weekStartUtc: DateTime.utc(2026, 10, 19),
    weekEndUtc: DateTime.utc(2026, 10, 26),
    occurredAt: DateTime.utc(2026, 10, 26, 12),
    createdAt: DateTime.utc(2026, 10, 26, 12),
    currentRank: rank,
    previousRank: previousRank,
    previousPeakRank: previousPeak,
    threshold: threshold,
    qualifiedStreamCount: streams,
    milestoneValue: milestone,
  );
}

void main() {
  group('SN-50 Batch 2: refined corrections to the approved catalog', () {
    test('P-001, P-002, P-010 to P-023 render exactly as approved', () {
      const expected = {
        'artist-hot100-d5':
            '"Paper Moon" by Mira Vale gives Mira Vale & Co a first Sonus Hot '
            '100 entry, at #7.',
        'artist-1-d6':
            '"Paper Moon" by Mira Vale gives Mira Vale & Co a first #1 on the '
            'Sonus Hot 100.',
        'artist-hot100-p4':
            'Mira Vale & Co cracks the Sonus Hot 100 for the first time: '
            '"Paper Moon" enters at #7 with 57 streams.',
        'artist-top-p3':
            'Head to head with Glass Harbor, Paper Moon pulls ahead as your #1 '
            'artist.',
        'artist-sim-p2':
            '3 songs, one artist: Mira Vale is all over the Top 10.',
        'artist-1-d1':
            'Mira Vale & Co earns a first #1 hit as "Paper Moon" tops the Sonus '
            'Hot 100.',
        'artist-1-n-d1':
            'Mira Vale & Co earns a third #1 hit as "Paper Moon" tops the Sonus '
            'Hot 100.',
        'artist-release-1-d1':
            'Mira Vale & Co earns a first #1 EP as Paper Moon tops the Sonus '
            'Albums & EPs chart.',
        'artist-release-1-n-d1':
            'Mira Vale & Co earns a third #1 release as Paper Moon tops the '
            'Sonus Albums & EPs chart.',
        'release-debut-1-d6':
            'A #1 debut for Mira Vale: the EP Paper Moon opens at the top of '
            'the Sonus Albums & EPs chart.',
        'release-debut-1-p5':
            'New EP, new #1: Paper Moon by Mira Vale debuts at the top.',
        'release-debut-1-p6':
            'Mira Vale lands a #1 debut: Paper Moon enters the Sonus Albums & '
            'EPs chart at the very top.',
        'song-debut-10-p4':
            'Out of the gate with 57 streams, "Paper Moon" by Mira Vale debuts '
            'in the Top 10 at #7.',
        'song-1-p4':
            '57 streams and the top spot: "Paper Moon" by Mira Vale hits '
            '#1!',
        'song-debut-p6':
            'New arrival alert: "Paper Moon" by Mira Vale makes its debut at #7 '
            'on the Sonus Hot 100.',
        'release-debut-p3':
            'Straight onto the chart: Paper Moon by Mira Vale enters at #7 with '
            '57 streams.',
      };
      for (final MapEntry(key: id, value: text) in expected.entries) {
        expect(_refined(id), text, reason: id);
        expect(_legacy(id), isNot(text), reason: '$id legacy is unchanged');
      }
    });

    test('P-001 and P-002 name the featured guest', () {
      expect(
        _refined('artist-hot100-d5', guest: 'Guest Voice'),
        startsWith('"Paper Moon" by Mira Vale featuring Guest Voice gives'),
      );
      expect(
        _refined('artist-1-d6', guest: 'Guest Voice'),
        startsWith('"Paper Moon" by Mira Vale featuring Guest Voice gives'),
      );
    });

    test('§6.4: guest-dropping lines leave refined stories with a guest '
        'only', () {
      for (final id in _guestLines) {
        final family = _familyOf(id);
        expect(
          _refinedIds(family, _facts(family, guest: 'Guest Voice')),
          isNot(contains(id)),
          reason: id,
        );
        expect(_refinedIds(family, _facts(family)), contains(id), reason: id);
        expect(
          [for (final v in MomentHeadlines.legacyOf(family)) v.id],
          contains(id),
          reason: '$id stays in the legacy catalog',
        );
      }
    });

    test('P-051: song-break-p4 never appears in refined stories', () {
      for (final guest in [null, 'Guest Voice']) {
        expect(
          _refinedIds(
            MomentFamily.songHot100Breakthrough,
            _facts(MomentFamily.songHot100Breakthrough, guest: guest),
          ),
          isNot(contains('song-break-p4')),
        );
      }
      expect([
        for (final v in MomentHeadlines.legacyOf(
          MomentFamily.songHot100Breakthrough,
        ))
          v.id,
      ], contains('song-break-p4'));
    });

    test('with a guest, no refined headline credits the song to its primary '
        'artist alone', () {
      final violations = <String>[];
      for (final family in MomentHeadlines.approvedFamilies.difference(
        _chartJumps,
      )) {
        for (final weekly in [false, true]) {
          final facts = _facts(family, guest: 'Guest Voice', weekly: weekly);
          for (final v in RefinedHeadlineCatalog.standard.of(family, facts)) {
            final text = v.build(facts);
            if (text.contains('"Paper Moon" by Mira Vale') &&
                !text.contains(
                  '"Paper Moon" by Mira Vale featuring Guest Voice',
                )) {
              violations.add(v.id);
            }
          }
        }
      }
      // song-weeks-p5 ("5 weeks in the Top 10 for "Song" by Artist.") was
      // missed by the contract's §6.4 list and has no approved exclusion yet.
      // Chart-jump lines are reviewed separately. Any other gap fails here.
      expect(violations.toSet(), {'song-weeks-p5'});
    });

    test('no approved family loses its last fitting line for a publisher', () {
      final profiles = <String, MomentFacts Function(MomentFamily, String?)>{
        'full': (f, g) => _facts(f, guest: g),
        'rank only': (f, g) => _facts(
          f,
          guest: g,
          previousRank: false,
          previousPeak: false,
          streams: false,
          owner: false,
          rival: false,
          ordinal: false,
          weeks: false,
          count: false,
        ),
        'no streams': (f, g) => _facts(f, guest: g, streams: false),
        'no previous rank': (f, g) =>
            _facts(f, guest: g, previousRank: false, previousPeak: false),
        'no rival': (f, g) => _facts(f, guest: g, rival: false),
      };
      for (final family in MomentHeadlines.approvedFamilies) {
        for (final MapEntry(key: name, value: build) in profiles.entries) {
          for (final guest in [null, 'Guest Voice']) {
            final facts = build(family, guest);
            for (final publisher in MomentPublisher.values) {
              bool fits(Iterable<HeadlineVariant> variants) => variants.any(
                (v) => v.publisher == publisher && v.fits(facts),
              );
              if (fits(MomentHeadlines.legacyOf(family))) {
                expect(
                  fits(RefinedHeadlineCatalog.standard.of(family, facts)),
                  isTrue,
                  reason: '${family.name} / $name / guest $guest / $publisher',
                );
              }
            }
          }
        }
      }
    });

    test(
      'composed refined stories with a guest never use an excluded line',
      () {
        final desk = MomentEditorialDesk(
          lookups: const _Lookups(),
          rules: ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1)),
        );
        final excluded = {..._guestLines, 'song-break-p4'};
        var stories = 0;
        for (final scope in [
          ChartMomentScope.allTime,
          ChartMomentScope.finalized,
        ]) {
          for (var i = 0; i < 24; i++) {
            final source = 'g$i';
            for (final events in [
              [_event(ChartMomentEventType.debut, scope, source, rank: 40)],
              [_event(ChartMomentEventType.debut, scope, source, rank: 6)],
              [_event(ChartMomentEventType.debut, scope, source, rank: 150)],
              [
                _event(
                  ChartMomentEventType.newPeak,
                  scope,
                  source,
                  rank: 4,
                  previousRank: 12,
                  previousPeak: 9,
                ),
              ],
              [
                _event(
                  ChartMomentEventType.reentry,
                  scope,
                  source,
                  rank: 30,
                  previousPeak: 12,
                ),
              ],
              [
                _event(
                  ChartMomentEventType.firstThresholdEntry,
                  scope,
                  source,
                  rank: 94,
                  previousRank: 106,
                  threshold: 100,
                ),
              ],
              [
                _event(
                  ChartMomentEventType.lifetimeStreamMilestone,
                  scope,
                  source,
                  rank: 12,
                  milestone: 100,
                  streams: 100,
                ),
              ],
            ]) {
              for (final story in desk.compose(
                const ChartMomentFeedAggregator().aggregate(events),
              )) {
                stories++;
                expect(excluded, isNot(contains(story.variantId)));
                final credit = '"Paper Moon $source" by Mira Vale';
                if (story.headline.contains(credit)) {
                  expect(
                    story.headline,
                    contains('$credit featuring Guest Voice'),
                  );
                }
              }
            }
          }
        }
        expect(stories, greaterThan(100));
      },
    );
  });
}
