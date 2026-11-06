import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/application/services/moment_chart_journey_service.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/pages/moment_story_page.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// App Update 1.1: a story's Chart Journey always belongs to the story's
/// own chart. Weekly and artist stories show an explicit unavailable
/// state; the all-time journey is never borrowed for them.
class _Lookups implements MomentLookups {
  @override
  String? artistName(String artistId) => 'Madison Beer';
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

const _song = ChartEntitySnapshot(
  entityId: 'song-angel',
  title: 'angel wings',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
);

const _artist = ChartEntitySnapshot(
  entityId: 'artist-madison',
  title: 'Madison Beer',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
);

const _rival = ChartEntitySnapshot(
  entityId: 'artist-tate',
  title: 'Tate McRae',
  artistId: 'artist-tate',
  artistName: 'Tate McRae',
);

final _at = DateTime.utc(2026, 11, 6, 15);

ChartMomentEvent _event(
  ChartMomentScope scope,
  ChartMomentEventType type, {
  ChartEntitySnapshot entity = _song,
  ChartEntitySnapshot? related,
  int? previousRank,
  int? currentRank,
  int? threshold,
}) {
  final key = '${scope.name}|${type.name}|${entity.entityId}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-1',
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: entity,
    relatedEntity: related,
    weekStartUtc: DateTime.utc(2026, 10, 25, 4),
    weekEndUtc: DateTime.utc(2026, 11, 1, 4),
    occurredAt: _at,
    createdAt: _at,
    previousRank: previousRank,
    currentRank: currentRank,
    threshold: threshold,
    previousPeakRank: 9,
    currentPeakRank: currentRank,
    qualifiedStreamCount: 30,
  );
}

MomentStory _story(List<ChartMomentEvent> events) => MomentEditorialDesk(
  lookups: _Lookups(),
  rules: ChartMomentRules(devicePolishFromUtc: DateTime.utc(2026, 11, 1)),
).compose(const ChartMomentFeedAggregator().aggregate(events)).first;

void main() {
  final calls = <(ChartType, String)>[];

  Future<MomentChartJourney?> loader(ChartType type, String id) async {
    calls.add((type, id));
    return MomentChartJourney(
      chartType: type,
      entityId: id,
      days: [
        ChartDayStanding(dayStartLocal: DateTime(2026, 11, 4), rank: 4),
        ChartDayStanding(dayStartLocal: DateTime(2026, 11, 5), rank: 3),
      ],
      totals: const ChartDayTotals(chartDays: 2, hot100Days: 2),
      peakRank: 3,
    );
  }

  setUp(calls.clear);

  Future<void> pump(WidgetTester tester, MomentStory story) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: MomentStoryPage(story: story, now: _at, journey: loader),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder unavailable(MomentStory story) => find.byKey(
    ValueKey<String>('moment-story-journey-unavailable-${story.id}'),
  );
  Finder chart(MomentStory story) =>
      find.byKey(ValueKey<String>('moment-story-journey-${story.id}'));

  testWidgets('an all-time story shows its own chart\'s journey', (
    tester,
  ) async {
    final story = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.rankRise,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    await pump(tester, story);

    expect(calls, [(ChartType.songs, 'song-angel')]);
    expect(chart(story), findsOneWidget);
    expect(unavailable(story), findsNothing);
    expect(find.textContaining('all-time Sonus Hot 100'), findsOneWidget);
  });

  testWidgets('a weekly story never borrows the all-time journey', (
    tester,
  ) async {
    final story = _story([
      _event(
        ChartMomentScope.finalized,
        ChartMomentEventType.newPeak,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    expect(story.item.scope, ChartMomentScope.finalized);
    await pump(tester, story);

    expect(calls, isEmpty, reason: 'nothing from another chart is read');
    expect(chart(story), findsNothing);
    expect(unavailable(story), findsOneWidget);
    expect(
      find.descendant(
        of: unavailable(story),
        matching: find.textContaining('weekly Sonus Hot 100'),
      ),
      findsOneWidget,
    );
    expect(find.text('Total Days on Chart'), findsNothing);
  });

  testWidgets('an artist story has no chart journey to show', (tester) async {
    final story = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.artistBecomesTopArtist,
        entity: _artist,
        related: _rival,
        currentRank: 1,
        threshold: 1,
      ),
    ]);
    await pump(tester, story);

    expect(calls, isEmpty);
    expect(chart(story), findsNothing);
    expect(unavailable(story), findsOneWidget);
  });
}
