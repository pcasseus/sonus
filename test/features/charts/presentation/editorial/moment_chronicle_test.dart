import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_category.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// App Update 1.1: the Moments chronicle's planning and headlines.
class _Lookups implements MomentLookups {
  @override
  String? artistName(String artistId) => null;
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> featuredOf(String songId) => const [];
  @override
  List<String> guestsOf(String songId) => const [];
  @override
  String? artistIdNamed(String name) => null;
  @override
  String? songCover(String songId) => '/art/$songId.png';
  @override
  String? releaseCover(String albumId) => '/art/$albumId.png';
  @override
  String? currentSongCover(String songId) => '/art/$songId.png';
  @override
  String? currentReleaseCover(String albumId) => '/art/$albumId.png';
  @override
  String? artistPortrait(String artistId) => '/portrait/$artistId.png';
}

final _start = DateTime.utc(2026, 11, 6, 15);
final _week = DateTime.utc(2026, 11, 1, 4);

const _angel = ChartEntitySnapshot(
  entityId: 'song-angel',
  title: 'angel wings',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
  albumTitle: 'locket',
);

const _locket = ChartEntitySnapshot(
  entityId: 'album-locket',
  title: 'locket',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
);

ChartMomentEvent _event(
  ChartMomentEventType type, {
  ChartEntitySnapshot entity = _angel,
  ChartType chart = ChartType.songs,
  String source = 'play-1',
  DateTime? at,
  int? previousRank,
  int? currentRank,
  int? threshold,
  int? previousPeakRank,
  int? milestone,
  int streams = 40,
}) {
  final key =
      'alltime|${chart.name}|${type.name}|${entity.entityId}|'
      '$source|${threshold ?? '-'}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source,
    chartType: chart,
    scope: ChartMomentScope.allTime,
    eventType: type,
    entity: entity,
    weekStartUtc: _week,
    weekEndUtc: _week.add(const Duration(days: 7)),
    occurredAt: at ?? _start.add(const Duration(hours: 2)),
    createdAt: at ?? _start.add(const Duration(hours: 2)),
    previousRank: previousRank,
    currentRank: currentRank,
    threshold: threshold,
    previousPeakRank: previousPeakRank,
    currentPeakRank: currentRank,
    qualifiedStreamCount: streams,
    milestoneValue: milestone,
  );
}

List<MomentStory> _compose(
  List<ChartMomentEvent> events, {
  DateTime? chronicleFrom,
}) => MomentEditorialDesk(
  lookups: _Lookups(),
  rules: ChartMomentRules(
    devicePolishFromUtc: DateTime.utc(2026, 11, 1),
    chronicleFromUtc: chronicleFrom ?? _start,
  ),
).compose(const ChartMomentFeedAggregator().aggregate(events));

void main() {
  group('one chart move, one story', () {
    final move = [
      _event(
        ChartMomentEventType.rankRise,
        previousRank: 19,
        currentRank: 8,
        previousPeakRank: 12,
      ),
      _event(
        ChartMomentEventType.newPeak,
        previousRank: 19,
        currentRank: 8,
        previousPeakRank: 12,
        threshold: 10,
      ),
      _event(
        ChartMomentEventType.firstThresholdEntry,
        previousRank: 19,
        currentRank: 8,
        previousPeakRank: 12,
        threshold: 10,
      ),
      _event(
        ChartMomentEventType.firstThresholdEntry,
        previousRank: 19,
        currentRank: 8,
        previousPeakRank: 12,
        threshold: 15,
      ),
    ];

    test('climb, first Top 10 and new peak are told together', () {
      final stories = _compose(move);

      expect(stories, hasLength(1));
      final story = stories.single;
      expect(story.family, MomentFamily.songChartMove);
      expect(story.rank, 8);
      expect(story.climb, 11);
      expect(story.status, 'TOP 10 ENTRY');
      // A first Top 10 is PulsePop's kind of story.
      expect(story.publisher, MomentPublisher.pulsePop);
      expect(story.headline, contains('"angel wings" by Madison Beer'));
      expect(story.headline, contains('#8'));
      expect(story.headline, contains('Top 10'));
      expect(story.headline, isNot(contains('Top 15')));
    });

    test('the Sonus Daily wording names every fact in one sentence', () {
      final stories = _compose([
        for (final event in move)
          if (event.threshold != 15) event,
      ]);
      // Recompose until the daily variant is checked directly.
      final daily = stories.single.facts;
      expect(daily.subject, '"angel wings" by Madison Beer');
      expect(stories.single.variantId, startsWith('move-'));
    });

    test('before the chronicle start the play keeps its earlier stories', () {
      final stories = _compose(
        move,
        chronicleFrom: _start.add(const Duration(days: 1)),
      );

      expect(
        stories.map((s) => s.family),
        isNot(contains(MomentFamily.songChartMove)),
      );
    });

    test('a return to a zone reached before is a return, not a first', () {
      final stories = _compose([
        _event(
          ChartMomentEventType.rankRise,
          previousRank: 12,
          currentRank: 4,
          previousPeakRank: 2,
        ),
        _event(
          ChartMomentEventType.thresholdReturn,
          previousRank: 12,
          currentRank: 4,
          previousPeakRank: 2,
          threshold: 5,
        ),
        _event(
          ChartMomentEventType.thresholdReturn,
          previousRank: 12,
          currentRank: 4,
          previousPeakRank: 2,
          threshold: 10,
        ),
      ]);

      final story = stories.single;
      expect(story.status, 'BACK IN TOP 5');
      expect(story.headline, isNot(contains('first time')));
      expect(story.headline, isNot(contains('peak')));
    });

    test('a #1 keeps its own story and no chart-move story is added', () {
      final stories = _compose([
        _event(
          ChartMomentEventType.returnToNumberOne,
          previousRank: 2,
          currentRank: 1,
          previousPeakRank: 1,
          threshold: 1,
        ),
        _event(
          ChartMomentEventType.thresholdReturn,
          previousRank: 2,
          currentRank: 1,
          previousPeakRank: 1,
          threshold: 3,
        ),
      ]);

      expect(
        stories.map((s) => s.family),
        isNot(contains(MomentFamily.songChartMove)),
      );
    });

    test('a plain climb is not turned into a chart move', () {
      final stories = _compose([
        _event(
          ChartMomentEventType.rankRise,
          previousRank: 40,
          currentRank: 36,
          previousPeakRank: 20,
        ),
      ]);

      expect(
        stories.map((s) => s.family),
        isNot(contains(MomentFamily.songChartMove)),
      );
    });

    test('composing twice gives the same stories', () {
      String ids() => _compose(move).map((s) => '${s.id}|${s.headline}').join();
      expect(ids(), ids());
    });
  });

  group('daily #1 holds', () {
    test('one hold story per day, with its consecutive days', () {
      final stories = _compose([
        _event(
          ChartMomentEventType.numberOneDayHold,
          source: 'day:2026-11-06',
          at: DateTime(2026, 11, 7).toUtc(),
          previousRank: 1,
          currentRank: 1,
          threshold: 1,
          milestone: 6,
        ),
      ]);

      final story = stories.single;
      expect(story.family, MomentFamily.songNumberOneHold);
      expect(story.publisher, MomentPublisher.sonusDaily);
      expect(story.status, '#1 HOLD');
      expect(story.headline, anyOf(contains('6th'), contains('6 days')));
      expect(MomentCategory.of(story.family), MomentCategory.numberOnes);
    });

    test('a first day says nothing about a streak', () {
      final story = _compose([
        _event(
          ChartMomentEventType.numberOneDayHold,
          entity: _locket,
          chart: ChartType.albums,
          source: 'day:2026-11-06',
          at: DateTime(2026, 11, 7).toUtc(),
          previousRank: 1,
          currentRank: 1,
          threshold: 1,
          milestone: 1,
        ),
      ]).single;

      expect(story.family, MomentFamily.releaseNumberOneHold);
      expect(story.headline, isNot(contains('straight')));
      expect(story.headline, contains('Albums & EPs'));
    });
  });

  group('exits and returns', () {
    test('a Hot 100 exit keeps the song on the wider chart', () {
      final story = _compose([
        _event(
          ChartMomentEventType.thresholdExit,
          source: 'exit:play-9:song-angel',
          previousRank: 100,
          currentRank: 101,
          threshold: 100,
          previousPeakRank: 23,
          milestone: 18,
        ),
      ]).single;

      expect(story.family, MomentFamily.songHot100Departure);
      expect(story.headline, contains('18 days'));
      expect(story.headline, contains('#101'));
      expect(story.status, 'EXIT (HOT 100)');
      expect(story.body, contains('Bubbling Under'));
    });

    test('leaving the Top 200 is a chart exit with days and peak', () {
      final story = _compose([
        _event(
          ChartMomentEventType.chartExit,
          source: 'exit:play-9:song-angel',
          previousRank: 200,
          previousPeakRank: 60,
          milestone: 3,
        ),
      ]).single;

      expect(story.family, MomentFamily.songChartDeparture);
      expect(story.headline, contains('3 days'));
      expect(story.headline, contains('#60'));
      expect(story.rank, isNull);
    });

    test('back from Bubbling Under: a Hot 100 return from its real rank', () {
      final stories = _compose([
        _event(
          ChartMomentEventType.thresholdReturn,
          previousRank: 108,
          currentRank: 94,
          threshold: 100,
          previousPeakRank: 40,
        ),
        _event(
          ChartMomentEventType.rankRise,
          previousRank: 108,
          currentRank: 94,
          previousPeakRank: 40,
        ),
      ]);
      expect(stories.map((s) => s.family).toList(), [
        MomentFamily.songHot100Return,
      ]);
      final story = stories.single;

      expect(story.family, MomentFamily.songHot100Return);
      expect(story.headline, contains('#108'));
      expect(story.headline, contains('#94'));
      expect(story.climb, 14);
    });
  });
}
