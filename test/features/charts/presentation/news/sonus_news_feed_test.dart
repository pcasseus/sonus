import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_moment_feed_copy.dart';
import 'package:sonus_next/features/charts/presentation/news/sonus_news_feed_page.dart';
import 'package:sonus_next/features/charts/presentation/news/sonus_news_story.dart';

// SN-48G: the Sonus News Feed over real Chart Moments. Fictional fixtures.
void main() {
  var counter = 0;

  ChartMomentEvent event(
    ChartMomentEventType type, {
    ChartType chart = ChartType.songs,
    ChartMomentScope scope = ChartMomentScope.finalized,
    String entityId = 'song-1',
    String title = 'Fixture Song',
    int day = 1,
  }) {
    final id = 'event-${counter++}';
    return ChartMomentEvent(
      id: id,
      deduplicationKey: id,
      chartType: chart,
      scope: scope,
      eventType: type,
      entity: ChartEntitySnapshot(
        entityId: entityId,
        title: title,
        artistName: 'Fixture Artist',
        artistId: 'artist-1',
      ),
      weekStartUtc: DateTime.utc(2026, 10, 5),
      weekEndUtc: DateTime.utc(2026, 10, 12),
      occurredAt: DateTime.utc(2026, 10, day, 12),
      createdAt: DateTime.utc(2026, 10, day, 12),
      currentRank: 1,
    );
  }

  ChartMomentFeedCopy copy(ChartMomentFeedItem item) => ChartMomentFeedCopy(
    headline: 'Headline for ${item.entity.title}',
    body: 'Body for ${item.dominantEventType.name}',
  );

  List<ChartMomentFeedItem> items(List<ChartMomentEvent> events) =>
      const ChartMomentFeedAggregator().aggregate(events);

  group('SonusNewsDesk', () {
    test('uses the Moments copy and artwork as given, inventing nothing', () {
      final stories = SonusNewsDesk(
        copyFor: copy,
        artworkFor: (item) => '/art/${item.entity.entityId}.png',
      ).stories(items([event(ChartMomentEventType.debut)]));

      expect(stories.single.headline, 'Headline for Fixture Song');
      expect(stories.single.body, 'Body for debut');
      expect(stories.single.artworkPath, '/art/song-1.png');
    });

    test('kickers name the weekly chart and whether the week is final', () {
      final desk = SonusNewsDesk(copyFor: copy);
      String kicker(ChartMomentEvent e) =>
          desk.stories(items([e])).single.kicker;

      expect(
        kicker(event(ChartMomentEventType.debut)),
        'Weekly Hot 100 · Final',
      );
      expect(
        kicker(event(ChartMomentEventType.debut, scope: ChartMomentScope.live)),
        'Weekly Hot 100 · This week',
      );
      expect(
        kicker(event(ChartMomentEventType.debut, chart: ChartType.albums)),
        'Weekly Top 200 · Final',
      );
      expect(
        kicker(event(ChartMomentEventType.lifetimeStreamMilestone)),
        'Listening milestone',
      );
    });

    test('Sonus Daily reports chart news; PulsePop covers momentum and '
        'milestones', () {
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.firstNumberOne),
        SonusNewsEdition.sonusDaily,
      );
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.debut),
        SonusNewsEdition.sonusDaily,
      );
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.rankFall),
        SonusNewsEdition.sonusDaily,
      );
      // The legacy PulsePop desk owned momentum stories.
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.rankRise),
        SonusNewsEdition.pulsePop,
      );
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.lifetimeStreamMilestone),
        SonusNewsEdition.pulsePop,
      );
      expect(
        SonusNewsDesk.editionFor(ChartMomentEventType.artistFirstNumberOneSong),
        SonusNewsEdition.pulsePop,
      );
    });

    test('features one headline story; routine movement is compact', () {
      final stories = SonusNewsDesk(copyFor: copy).stories(
        items([
          event(
            ChartMomentEventType.firstNumberOne,
            entityId: 'a',
            title: 'Topper',
            day: 3,
          ),
          event(
            ChartMomentEventType.newPeak,
            entityId: 'b',
            title: 'Peaker',
            day: 2,
          ),
          event(
            ChartMomentEventType.rankFall,
            entityId: 'c',
            title: 'Faller',
            day: 1,
          ),
        ]),
      );
      SonusNewsFormat formatOf(String title) => stories
          .singleWhere((s) => s.headline == 'Headline for $title')
          .format;

      expect(
        stories.where((s) => s.format == SonusNewsFormat.featured),
        hasLength(1),
      );
      expect(formatOf('Faller'), SonusNewsFormat.compact);
      expect([
        formatOf('Topper'),
        formatOf('Peaker'),
      ], containsAll([SonusNewsFormat.featured, SonusNewsFormat.standard]));
    });
  });

  group('SonusNewsFeedPage', () {
    Future<void> pump(
      WidgetTester tester, {
      required ChartMomentRepository? moments,
      SonusAppearanceSpec spec = const SonusAppearanceSpec(),
      Size size = const Size(411, 1400),
      double textScale = 1,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(spec),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: SonusNewsFeedPage(moments: moments, copyFor: copy),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<ChartMomentEvent> fixtures() => [
      event(
        ChartMomentEventType.firstNumberOne,
        entityId: 'top',
        title: 'An Exceptionally Long Fixture Chart Topper Title',
        day: 9,
      ),
      event(
        ChartMomentEventType.lifetimeStreamMilestone,
        entityId: 'stream',
        title: 'Milestone Song',
        day: 8,
      ),
      event(ChartMomentEventType.rankRise, entityId: 'riser', day: 7),
    ];

    testWidgets('shows the stories and filters by edition', (tester) async {
      await pump(tester, moments: _Moments(fixtures()));

      expect(find.text('Sonus News'), findsWidgets);
      expect(
        find.text(
          'Headline for An Exceptionally Long Fixture Chart Topper Title',
        ),
        findsOneWidget,
      );
      expect(find.text('Headline for Milestone Song'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('sonus-news-edition-pulsePop')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Headline for Milestone Song'), findsOneWidget);
      expect(
        find.text(
          'Headline for An Exceptionally Long Fixture Chart Topper Title',
        ),
        findsNothing,
      );
    });

    testWidgets('without Moments it says so honestly', (tester) async {
      await pump(tester, moments: _Moments(const []));

      expect(
        find.byKey(const ValueKey<String>('sonus-news-empty')),
        findsOneWidget,
      );
      expect(find.text('No news yet'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      await pump(tester, moments: _Moments(const [], fail: true));

      expect(
        find.byKey(const ValueKey<String>('sonus-news-error')),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          moments: _Moments(fixtures()),
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 3000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        await pump(
          tester,
          moments: _Moments(fixtures()),
          spec: SonusAppearanceSpec(decoration: level),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _Moments implements ChartMomentRepository {
  _Moments(this.events, {this.fail = false});

  final List<ChartMomentEvent> events;
  final bool fail;

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async {
    if (fail) throw StateError('moments failed');
    return events;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
