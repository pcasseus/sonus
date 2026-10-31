// SN-50 Batch 0: Moments published before the refined rules must render
// byte-identically forever (contract §5, §8). Headlines are composed from
// stored events each time the feed is shown and the variant is chosen by a
// hash over the fitting lines, so any change to the legacy catalog, its
// order or the legacy helpers would rewrite old stories. These goldens were
// captured at f062551, before any catalog change. They are written only
// when missing; never regenerate them to make a change pass.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';
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
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

const _goldenDir = 'test/features/charts/presentation/editorial/goldens';
const _storiesGolden = '$_goldenDir/legacy_moments_v1.json';
const _catalogGolden = '$_goldenDir/legacy_catalog_v1.json';
const _sweepGolden = '$_goldenDir/legacy_selection_sweep_v1.json';

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Artist $artistId';

  @override
  ReleaseFormat? formatOf(String albumId) =>
      albumId.contains('ep') ? ReleaseFormat.ep : ReleaseFormat.album;

  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;

  /// Songs whose id ends in "-f" have a featured performer.
  @override
  List<String> featuredOf(String songId) =>
      songId.endsWith('-f') ? const ['Guest Voice'] : const [];

  @override
  String? artistIdNamed(String name) =>
      name.startsWith('Artist ') ? name.substring(7) : null;

  @override
  String? songCover(String songId) => 'covers/$songId.jpg';

  @override
  String? releaseCover(String albumId) => 'covers/$albumId.jpg';

  @override
  String? currentSongCover(String songId) => songCover(songId);

  @override
  String? currentReleaseCover(String albumId) => releaseCover(albumId);

  @override
  String? artistPortrait(String artistId) => 'portraits/$artistId.jpg';
}

final _weekStart = DateTime.utc(2026, 10, 19);
final _occurred = DateTime.utc(2026, 10, 26, 12);

ChartEntitySnapshot _song(String id, {String artist = 'mira'}) =>
    ChartEntitySnapshot(
      entityId: id,
      title: 'Song $id',
      artistId: artist,
      artistName: 'Artist $artist',
      albumTitle: 'Album of $id',
    );

ChartEntitySnapshot _release(String id, {String artist = 'mira'}) =>
    ChartEntitySnapshot(
      entityId: id,
      title: 'Release $id',
      artistId: artist,
      artistName: 'Artist $artist',
    );

ChartEntitySnapshot _artist(String id) => ChartEntitySnapshot(
  entityId: id,
  title: 'Artist $id',
  artistId: id,
  artistName: 'Artist $id',
);

/// One story's events, keyed by a stable scenario name.
typedef _Scenario =
    List<ChartMomentEvent> Function(
      ChartMomentScope scope,
      String source,
      String suffix,
    );

ChartMomentEvent _event(
  ChartMomentEventType type,
  ChartEntitySnapshot entity, {
  required ChartMomentScope scope,
  required String source,
  ChartType chartType = ChartType.songs,
  int? rank,
  int? previousRank,
  int? previousPeak,
  int? threshold,
  int? streams,
  int? milestone,
  ChartEntitySnapshot? related,
}) {
  final key = '${scope.name}|${type.name}|${entity.entityId}|$source';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source,
    chartType: chartType,
    scope: scope,
    eventType: type,
    entity: entity,
    relatedEntity: related,
    weekStartUtc: _weekStart,
    weekEndUtc: _weekStart.add(const Duration(days: 7)),
    occurredAt: _occurred,
    createdAt: _occurred,
    currentRank: rank,
    previousRank: previousRank,
    previousPeakRank: previousPeak,
    threshold: threshold,
    qualifiedStreamCount: streams,
    milestoneValue: milestone,
  );
}

typedef T = ChartMomentEventType;

/// Song stories; [suffix] "-f" gives the song a featured performer.
final Map<String, _Scenario> _songScenarios = {
  'debut-1': (scope, src, x) {
    final s = _song('debut1$x');
    return [
      _event(T.debut, s, scope: scope, source: src, rank: 1, streams: 40),
      _event(T.firstNumberOne, s, scope: scope, source: src, rank: 1),
    ];
  },
  'debut-5': (scope, src, x) => [
    _event(
      T.debut,
      _song('debut5$x'),
      scope: scope,
      source: src,
      rank: 5,
      streams: 30,
    ),
  ],
  'debut-40': (scope, src, x) => [
    _event(
      T.debut,
      _song('debut40$x'),
      scope: scope,
      source: src,
      rank: 40,
      streams: 12,
    ),
  ],
  'debut-150': (scope, src, x) => [
    _event(T.debut, _song('debut150$x'), scope: scope, source: src, rank: 150),
  ],
  'first-1-rival': (scope, src, x) => [
    _event(
      T.firstNumberOne,
      _song('first1$x'),
      scope: scope,
      source: src,
      rank: 1,
      previousRank: 3,
      streams: 80,
      related: _song('rival', artist: 'ilse'),
    ),
  ],
  'first-1': (scope, src, x) => [
    _event(
      T.firstNumberOne,
      _song('first1n$x'),
      scope: scope,
      source: src,
      rank: 1,
      previousRank: 4,
    ),
  ],
  'return-1': (scope, src, x) => [
    _event(
      T.returnToNumberOne,
      _song('return1$x'),
      scope: scope,
      source: src,
      rank: 1,
      previousRank: 2,
      previousPeak: 1,
      related: _song('rival2', artist: 'ilse'),
    ),
  ],
  'new-peak': (scope, src, x) => [
    _event(
      T.newPeak,
      _song('peak$x'),
      scope: scope,
      source: src,
      rank: 4,
      previousRank: 12,
      previousPeak: 9,
      streams: 57,
    ),
  ],
  'peak-match': (scope, src, x) => [
    _event(
      T.peakMatch,
      _song('match$x'),
      scope: scope,
      source: src,
      rank: 4,
      previousRank: 7,
      previousPeak: 4,
    ),
  ],
  'rise': (scope, src, x) => [
    _event(
      T.rankRise,
      _song('rise$x'),
      scope: scope,
      source: src,
      rank: 20,
      previousRank: 45,
    ),
  ],
  'bu-rise': (scope, src, x) => [
    _event(
      T.rankRise,
      _song('burise$x'),
      scope: scope,
      source: src,
      rank: 139,
      previousRank: 171,
    ),
  ],
  'fall': (scope, src, x) => [
    _event(
      T.rankFall,
      _song('fall$x'),
      scope: scope,
      source: src,
      rank: 50,
      previousRank: 20,
    ),
  ],
  'reentry': (scope, src, x) => [
    _event(
      T.reentry,
      _song('reentry$x'),
      scope: scope,
      source: src,
      rank: 30,
      previousPeak: 12,
    ),
  ],
  'streams': (scope, src, x) => [
    _event(
      T.lifetimeStreamMilestone,
      _song('streams$x'),
      scope: scope,
      source: src,
      rank: 12,
      milestone: 100,
      streams: 100,
    ),
  ],
  'breakthrough': (scope, src, x) => [
    _event(
      T.firstThresholdEntry,
      _song('break$x'),
      scope: scope,
      source: src,
      rank: 94,
      previousRank: 106,
      threshold: 100,
    ),
  ],
  'career-hot100': (scope, src, x) {
    final s = _song('carhot$x');
    return [
      _event(T.debut, s, scope: scope, source: src, rank: 60),
      _event(
        T.artistFirstThresholdSong,
        s,
        scope: scope,
        source: src,
        rank: 60,
        threshold: 100,
        milestone: 1,
      ),
    ];
  },
  'career-top10': (scope, src, x) {
    final s = _song('cartop$x');
    return [
      _event(
        T.newPeak,
        s,
        scope: scope,
        source: src,
        rank: 8,
        previousRank: 14,
        previousPeak: 14,
      ),
      _event(
        T.artistFirstThresholdSong,
        s,
        scope: scope,
        source: src,
        rank: 8,
        threshold: 10,
        milestone: 1,
      ),
    ];
  },
  'career-nth-top10': (scope, src, x) {
    final s = _song('carnth$x');
    return [
      _event(
        T.newPeak,
        s,
        scope: scope,
        source: src,
        rank: 6,
        previousRank: 11,
        previousPeak: 11,
      ),
      _event(
        T.artistNthThresholdSong,
        s,
        scope: scope,
        source: src,
        rank: 6,
        threshold: 10,
        milestone: 2,
      ),
    ];
  },
  'career-first-1': (scope, src, x) {
    final s = _song('carone$x');
    return [
      _event(
        T.firstNumberOne,
        s,
        scope: scope,
        source: src,
        rank: 1,
        previousRank: 2,
      ),
      _event(
        T.artistFirstNumberOneSong,
        s,
        scope: scope,
        source: src,
        rank: 1,
        threshold: 1,
        milestone: 1,
      ),
    ];
  },
  'career-nth-1': (scope, src, x) {
    final s = _song('carnone$x');
    return [
      _event(
        T.firstNumberOne,
        s,
        scope: scope,
        source: src,
        rank: 1,
        previousRank: 2,
      ),
      _event(
        T.artistNthNumberOneSong,
        s,
        scope: scope,
        source: src,
        rank: 1,
        threshold: 1,
        milestone: 3,
      ),
    ];
  },
  'weeks-top10': (scope, src, x) => [
    _event(
      T.consecutiveThresholdWeeksMilestone,
      _song('weeks$x'),
      scope: scope,
      source: src,
      rank: 6,
      threshold: 10,
      milestone: 5,
    ),
  ],
  'weeks-chart': (scope, src, x) => [
    _event(
      T.totalWeeksMilestone,
      _song('weeksall$x'),
      scope: scope,
      source: src,
      rank: 40,
      milestone: 10,
    ),
  ],
};

final Map<String, _Scenario> _releaseScenarios = {
  'debut-1': (scope, src, x) {
    final r = _release('rdebut1$x');
    return [
      _event(
        T.debut,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
        streams: 90,
      ),
      _event(
        T.firstNumberOne,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
      ),
    ];
  },
  'debut-8': (scope, src, x) => [
    _event(
      T.debut,
      _release('rdebut8ep$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 8,
      streams: 25,
    ),
  ],
  'debut-60': (scope, src, x) => [
    _event(
      T.debut,
      _release('rdebut60$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 60,
    ),
  ],
  'first-1-rival': (scope, src, x) => [
    _event(
      T.firstNumberOne,
      _release('rfirst1$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 1,
      previousRank: 3,
      related: _release('rrival', artist: 'ilse'),
    ),
  ],
  'return-1': (scope, src, x) => [
    _event(
      T.returnToNumberOne,
      _release('rreturn$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 1,
      previousRank: 2,
      previousPeak: 1,
    ),
  ],
  'new-peak': (scope, src, x) => [
    _event(
      T.newPeak,
      _release('rpeak$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 3,
      previousRank: 7,
      previousPeak: 5,
      streams: 44,
    ),
  ],
  'reentry': (scope, src, x) => [
    _event(
      T.reentry,
      _release('rreentry$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 20,
      previousPeak: 4,
    ),
  ],
  'streams': (scope, src, x) => [
    _event(
      T.lifetimeStreamMilestone,
      _release('rstreams$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 9,
      milestone: 1000,
      streams: 1000,
    ),
  ],
  'career-first-1': (scope, src, x) {
    final r = _release('rcarone$x');
    return [
      _event(
        T.firstNumberOne,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
        previousRank: 2,
      ),
      _event(
        T.artistFirstNumberOneAlbum,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
        threshold: 1,
        milestone: 1,
      ),
    ];
  },
  'career-nth-1': (scope, src, x) {
    final r = _release('rcarnone$x');
    return [
      _event(
        T.firstNumberOne,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
        previousRank: 2,
      ),
      _event(
        T.artistNthNumberOneAlbum,
        r,
        scope: scope,
        source: src,
        chartType: ChartType.albums,
        rank: 1,
        threshold: 1,
        milestone: 2,
      ),
    ];
  },
  'weeks': (scope, src, x) => [
    _event(
      T.consecutiveThresholdWeeksMilestone,
      _release('rweeks$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 1,
      threshold: 1,
      milestone: 3,
    ),
  ],
};

final Map<String, _Scenario> _artistScenarios = {
  'top-artist': (scope, src, x) => [
    _event(
      T.artistBecomesTopArtist,
      _artist('mira$x'),
      scope: scope,
      source: src,
      rank: 1,
      related: _artist('ilse'),
    ),
  ],
  'artist-streams': (scope, src, x) => [
    _event(
      T.artistStreamMilestone,
      _artist('mira$x'),
      scope: scope,
      source: src,
      milestone: 1000,
    ),
  ],
  'simultaneous-songs': (scope, src, x) => [
    _event(
      T.artistSimultaneousThresholdSongs,
      _song('simA$x'),
      scope: scope,
      source: src,
      rank: 3,
      threshold: 10,
      milestone: 3,
      related: _song('simB$x'),
    ),
  ],
  'simultaneous-releases': (scope, src, x) => [
    _event(
      T.artistSimultaneousThresholdAlbums,
      _release('rsimA$x'),
      scope: scope,
      source: src,
      chartType: ChartType.albums,
      rank: 2,
      threshold: 10,
      milestone: 2,
      related: _release('rsimB$x'),
    ),
  ],
};

const _sources = ['play-0', 'play-1', 'play-2', 'play-3'];
const _scopes = [ChartMomentScope.allTime, ChartMomentScope.finalized];

/// Every scenario composed on its own, keyed by scenario, scope, featured
/// flag and source, as the stories a desk with [rules] publishes.
Map<String, Object?> _renderAll(ChartMomentRules rules) {
  final desk = MomentEditorialDesk(lookups: const _Lookups(), rules: rules);
  final out = <String, Object?>{};

  void run(String group, Map<String, _Scenario> scenarios, List<String> xs) {
    for (final MapEntry(key: name, value: build) in scenarios.entries) {
      for (final scope in _scopes) {
        for (final x in xs) {
          for (final src in _sources) {
            final List<ChartMomentFeedItem> feed =
                const ChartMomentFeedAggregator().aggregate(
                  build(scope, src, x),
                );
            final key =
                '$group/$name/${scope.name}/${x.isEmpty ? 'plain' : 'featured'}/$src';
            out[key] = [for (final story in desk.compose(feed)) _story(story)];
          }
        }
      }
    }
  }

  run('song', _songScenarios, const ['', '-f']);
  run('release', _releaseScenarios, const ['']);
  run('artist', _artistScenarios, const ['']);
  return out;
}

/// Which publisher and line the earlier rules pick for each scenario and
/// scope over 500 story ids (contract §8 item 2). Catches any change to a
/// family's size, order or fitting set, which would re-pick old headlines.
Map<String, Object?> _sweep(ChartMomentRules rules) {
  final desk = MomentEditorialDesk(lookups: const _Lookups(), rules: rules);
  final out = <String, Object?>{};
  for (final (group, scenarios) in [
    ('song', _songScenarios),
    ('release', _releaseScenarios),
    ('artist', _artistScenarios),
  ]) {
    for (final MapEntry(key: name, value: build) in scenarios.entries) {
      for (final scope in _scopes) {
        final picks = <String>[];
        for (var i = 0; i < 500; i++) {
          final stories = desk.compose(
            const ChartMomentFeedAggregator().aggregate(
              build(scope, 'sweep-$i', ''),
            ),
          );
          picks.add(
            [
              for (final s in stories) '${s.publisher.name}:${s.variantId}',
            ].join('+'),
          );
        }
        if (picks.any((pick) => pick.isNotEmpty)) {
          out['$group/$name/${scope.name}'] = picks;
        }
      }
    }
  }
  return out;
}

Map<String, Object?> _story(MomentStory s) => {
  'id': s.id,
  'family': s.family.name,
  'publisher': s.publisher.name,
  'variantId': s.variantId,
  'headline': s.headline,
  'body': s.body,
  'kicker': s.kicker,
  'status': s.status,
  'rank': s.rank,
  'layout': s.visual.layout.name,
  'left':
      '${s.visual.left.kind.name}:${s.visual.left.entityId}:${s.visual.left.path}',
  'right': s.visual.right == null
      ? null
      : '${s.visual.right!.kind.name}:${s.visual.right!.entityId}:${s.visual.right!.path}',
};

/// Facts that let every legacy headline render.
MomentFacts _facts(MomentFamily family, {required bool weekly, String? guest}) {
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
    title: 'Paper Moon',
    artist: 'Mira Vale',
    ownerName: 'Mira Vale & Co',
    album: 'Night Signals',
    format: releaseFamily ? ReleaseFormat.ep : null,
    rank: rank,
    previousRank: family == MomentFamily.songHot100Breakthrough
        ? 106
        : rank + 23,
    previousPeak: rank + 2,
    streams: 57,
    milestone: 100,
    ordinal: 3,
    threshold: 10,
    weeks: 5,
    rivalTitle: 'Glass Harbor',
    rivalArtist: 'Ilse Moor',
    featured: guest,
    consecutive: true,
    count: 3,
    thresholds: const [75, 50, 40],
    jump: const ChartJumpFacts(
      fromRank: 47,
      toRank: 7,
      weeks: 3,
      weekStreams: 245,
      previousWeekStreams: 235,
    ),
  );
}

/// Every legacy headline: id, publisher, needs, and its text with full
/// facts (career and weekly, with and without a featured performer).
Map<String, Object?> _catalog() => {
  for (final family in MomentHeadlines.families)
    family.name: [
      for (final v in MomentHeadlines.of(family))
        {
          'id': v.id,
          'publisher': v.publisher.name,
          'requires': [for (final r in v.requires) r.name]..sort(),
          for (final (label, weekly, guest) in const [
            ('career', false, null),
            ('weekly', true, null),
            ('careerFeatured', false, 'Guest Voice'),
            ('weeklyFeatured', true, 'Guest Voice'),
          ])
            label: _render(
              () => v.build(_facts(family, weekly: weekly, guest: guest)),
            ),
        },
    ],
};

String _render(String Function() build) {
  try {
    return build();
  } catch (error) {
    return '<throws ${error.runtimeType}>';
  }
}

String _encode(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

/// Compares [actual] with the golden at [path]; writes it only when it is
/// missing, and then fails so the capture is noticed.
void _expectGolden(String path, Object? actual) {
  final file = File(path);
  final encoded = _encode(actual);
  if (!file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
    fail('Golden $path was missing and has been captured; rerun.');
  }
  final golden = jsonDecode(file.readAsStringSync());
  expect(jsonDecode(encoded), golden);
}

class _MarkerStore implements MomentRulesActivationStore {
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads++;
    return '2026-10-01T00:00:00.000Z';
  }

  @override
  Future<void> write(String activatedAtUtc) async => writes++;
}

void main() {
  group('SN-50 Batch 0: legacy Moments render byte-identically', () {
    test('every legacy headline keeps its id, order, publisher, needs and '
        'text', () {
      _expectGolden(_catalogGolden, _catalog());
    });

    test('stories under the earlier rules match the golden', () {
      _expectGolden(_storiesGolden, _renderAll(ChartMomentRules.legacy));
    });

    test('the earlier rules pick the same line over 500 story ids', () {
      _expectGolden(_sweepGolden, _sweep(ChartMomentRules.legacy));
    });

    test('stories before the activation instant match the same golden', () {
      final preActivation = ChartMomentRules(
        activatedAtUtc: DateTime.utc(2027, 1, 1),
      );
      _expectGolden(_storiesGolden, _renderAll(preActivation));
    });

    test('a stored marker with the flag off reads nothing and renders the '
        'same golden', () async {
      final store = _MarkerStore();
      final rules = await MomentRulesActivation(
        store: store,
        approved: false,
      ).rules();

      expect(rules.activatedAtUtc, isNull);
      expect(store.reads, 0);
      expect(store.writes, 0);
      _expectGolden(_storiesGolden, _renderAll(rules));
    });

    test('the build running these tests has the flag off', () {
      expect(MomentRulesActivation.buildApproved, isFalse);
    });

    test('the fixtures cover the legacy families', () {
      final families = <String>{
        for (final stories in _renderAll(ChartMomentRules.legacy).values)
          for (final story in stories! as List)
            (story as Map)['family'] as String,
      };
      expect(families.length, greaterThanOrEqualTo(20), reason: '$families');
    });
  });
}
