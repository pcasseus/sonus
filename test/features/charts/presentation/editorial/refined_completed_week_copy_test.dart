// SN-50 Batch 1 (contract §6.3, P-003 to P-009): refined stories about a
// finished week never say "this week" or "this stream". Stories under the
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
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/charts/presentation/editorial/refined_headline_catalog.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

class _Lookups implements MomentLookups {
  const _Lookups();

  @override
  String? artistName(String artistId) => 'Artist $artistId';
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

MomentFacts _facts(
  MomentFamily family, {
  required bool weekly,
  required bool refined,
  ChartType? chartType,
  int? rank,
}) {
  final releaseFamily = family.isRelease;
  final numberOne =
      family.isNumberOne || family == MomentFamily.artistTopArtist;
  final at =
      rank ??
      switch (family) {
        _ when numberOne => 1,
        MomentFamily.songBubblingUnderDebut => 106,
        MomentFamily.songHot100Breakthrough => 94,
        _ => 7,
      };
  return MomentFacts(
    chartType:
        chartType ?? (releaseFamily ? ChartType.albums : ChartType.songs),
    weekly: weekly,
    refined: refined,
    title: 'Paper Moon',
    artist: 'Mira Vale',
    ownerName: 'Mira Vale & Co',
    album: 'Night Signals',
    format: releaseFamily ? ReleaseFormat.ep : null,
    rank: at,
    previousRank: family == MomentFamily.songHot100Breakthrough ? 106 : at + 23,
    previousPeak: at + 2,
    streams: 57,
    milestone: 100,
    ordinal: 3,
    threshold: 10,
    weeks: 5,
    rivalTitle: 'Glass Harbor',
    rivalArtist: 'Ilse Moor',
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

ChartMomentEvent _peak(
  ChartMomentScope scope, {
  required int previousRank,
  required int previousPeak,
}) {
  final song = ChartEntitySnapshot(
    entityId: 'song-peak',
    title: 'Paper Moon',
    artistId: 'mira',
    artistName: 'Artist mira',
  );
  final key = '${scope.name}|newPeak|song-peak|p';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'p',
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.newPeak,
    entity: song,
    weekStartUtc: DateTime.utc(2026, 10, 19),
    weekEndUtc: DateTime.utc(2026, 10, 26),
    occurredAt: DateTime.utc(2026, 10, 26, 12),
    createdAt: DateTime.utc(2026, 10, 26, 12),
    currentRank: 4,
    previousRank: previousRank,
    previousPeakRank: previousPeak,
  );
}

/// A song peak story whose headline states only the rank, so the body
/// carries the previous position.
String? _peakBody(
  ChartMomentScope scope, {
  required ChartMomentRules rules,
  required int previousRank,
  required int previousPeak,
}) {
  final rankOnly = RefinedHeadlineCatalog(
    overrides: [
      for (final v in MomentHeadlines.legacyOf(MomentFamily.songNewPeak))
        RefinedOverride(
          v.id,
          (f) => '${f.subject} is at #${f.rank}.',
          requires: const {MomentFact.rank},
          approved: true,
        ),
    ],
  );
  final stories =
      MomentEditorialDesk(
        lookups: const _Lookups(),
        rules: rules,
        refinedCatalog: rankOnly,
      ).compose(
        const ChartMomentFeedAggregator().aggregate([
          _peak(scope, previousRank: previousRank, previousPeak: previousPeak),
        ]),
      );
  return stories.single.body;
}

void main() {
  final activated = ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 1, 1));

  group('SN-50 Batch 1: completed-week wording for refined stories', () {
    test('P-003/P-004: refined weekly stories name the weekly chart', () {
      String chart(ChartType type, int rank, {required bool refined}) => _facts(
        MomentFamily.songDebut,
        weekly: true,
        refined: refined,
        chartType: type,
        rank: rank,
      ).chart;

      expect(
        chart(ChartType.songs, 7, refined: true),
        'the weekly Sonus Hot 100',
      );
      expect(
        chart(ChartType.songs, 140, refined: true),
        'the weekly Sonus Bubbling Under',
      );
      expect(
        chart(ChartType.albums, 7, refined: true),
        'the weekly Sonus Albums & EPs chart',
      );
      expect(
        chart(ChartType.albums, 140, refined: true),
        'the weekly Sonus Albums & EPs chart',
      );
      // Earlier stories keep their words.
      expect(
        chart(ChartType.songs, 7, refined: false),
        "this week's Sonus Hot 100",
      );
      expect(
        chart(ChartType.songs, 140, refined: false),
        "this week's Sonus Hot 100",
      );
      expect(
        chart(ChartType.albums, 7, refined: false),
        "this week's Sonus Albums & EPs chart",
      );
    });

    test('career stories keep the plain chart name', () {
      for (final refined in [true, false]) {
        expect(
          _facts(MomentFamily.songDebut, weekly: false, refined: refined).chart,
          'the Sonus Hot 100',
        );
        expect(
          _facts(
            MomentFamily.songDebut,
            weekly: false,
            refined: refined,
            rank: 140,
          ).chart,
          'Sonus Bubbling Under',
        );
      }
    });

    test('P-005/P-006: a refined weekly body names the week before', () {
      expect(
        _peakBody(
          ChartMomentScope.finalized,
          rules: activated,
          previousRank: 12,
          previousPeak: 9,
        ),
        contains('The song was at #12 the week before.'),
      );
      expect(
        _peakBody(
          ChartMomentScope.finalized,
          rules: activated,
          previousRank: 9,
          previousPeak: 9,
        ),
        contains('The song was at #9 the week before, its best until then.'),
      );
    });

    test('career bodies and earlier weekly bodies keep their words', () {
      expect(
        _peakBody(
          ChartMomentScope.allTime,
          rules: activated,
          previousRank: 12,
          previousPeak: 9,
        ),
        contains('The song was at #12 before this stream.'),
      );
      expect(
        _peakBody(
          ChartMomentScope.finalized,
          rules: ChartMomentRules.legacy,
          previousRank: 12,
          previousPeak: 9,
        ),
        isNot(contains('the week before')),
      );
    });

    test('P-007 to P-009 render exactly in refined stories only', () {
      final catalog = RefinedHeadlineCatalog.standard;
      String refined(MomentFamily family, String id) {
        final facts = _facts(family, weekly: true, refined: true);
        return catalog
            .of(family, facts)
            .singleWhere((v) => v.id == id)
            .build(facts);
      }

      String legacy(MomentFamily family, String id) =>
          MomentHeadlines.legacyOf(family)
              .singleWhere((v) => v.id == id)
              .build(_facts(family, weekly: true, refined: false));

      expect(
        refined(MomentFamily.songBiggestGainer, 'song-gainer-d6'),
        'No song climbed further in the chart week than "Paper Moon" by Mira '
        'Vale, up 23 places to #7.',
      );
      expect(
        refined(MomentFamily.songBiggestGainer, 'song-gainer-p6'),
        '"Paper Moon" leads every climber of the chart week, rising 23 places '
        'to #7.',
      );
      expect(
        refined(MomentFamily.artistSimultaneous, 'artist-sim-p4'),
        'Mira Vale lands 3 songs in the Top 10 of the weekly Sonus Hot 100.',
      );
      expect(
        legacy(MomentFamily.songBiggestGainer, 'song-gainer-d6'),
        contains('this week'),
      );
      expect(
        legacy(MomentFamily.artistSimultaneous, 'artist-sim-p4'),
        contains('this week'),
      );
    });

    test('no refined weekly headline of an approved family says "this '
        'week"', () {
      final catalog = RefinedHeadlineCatalog.standard;
      for (final family in MomentHeadlines.approvedFamilies) {
        for (final rank in [7, 140]) {
          final facts = _facts(family, weekly: true, refined: true, rank: rank);
          for (final v in catalog.of(family, facts)) {
            final text = v.build(facts).toLowerCase();
            expect(text, isNot(contains('this week')), reason: v.id);
            expect(text, isNot(contains('this stream')), reason: v.id);
          }
        }
      }
    });
  });
}
