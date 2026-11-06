import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/news/moment_feed_cards.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

import '../../../../support/device_layout.dart';

/// App Update 1.1 device acceptance: a Chart Bulletin adapts to its
/// content. Short stories keep the words beside the picture; a long
/// headline or an update thread flows beneath it, so no blank column is
/// left under the artwork. Measured in real Roboto at real phone widths.
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

ChartEntitySnapshot _song(String id, String title, String artist) =>
    ChartEntitySnapshot(
      entityId: id,
      title: title,
      artistId: 'artist-$artist',
      artistName: artist,
    );

final _day = DateTime(2026, 11, 5);

ChartMomentEvent _rise(
  ChartEntitySnapshot entity, {
  required int from,
  required int to,
  int hour = 10,
  ChartMomentScope scope = ChartMomentScope.allTime,
  ChartMomentEventType type = ChartMomentEventType.rankRise,
}) {
  final at = _day.add(Duration(hours: hour)).toUtc();
  final key = '${scope.name}|${entity.entityId}|$hour|${type.name}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-${entity.entityId}-$hour',
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: entity,
    weekStartUtc: DateTime.utc(2026, 11, 1, 4),
    weekEndUtc: DateTime.utc(2026, 11, 8, 5),
    occurredAt: at,
    createdAt: at,
    previousRank: from,
    currentRank: to,
    previousPeakRank: 6,
    currentPeakRank: 6,
    qualifiedStreamCount: 30,
  );
}

List<MomentStory> _compose(List<ChartMomentEvent> events) =>
    MomentEditorialDesk(
      lookups: _Lookups(),
      rules: ChartMomentRules(devicePolishFromUtc: DateTime.utc(2026, 11, 1)),
    ).compose(const ChartMomentFeedAggregator().aggregate(events));

final _short = _song('song-tft', 'TIT FOR TAT', 'Tate McRae');
final _long = _song(
  'song-housewife-live',
  'Housewife [Live From Victoria Secret Fashion Show]',
  'Tate McRae',
);

void main() {
  setUpAll(loadRealRoboto);

  Future<void> pump(
    WidgetTester tester,
    MomentStory story, {
    double width = 384,
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: withRealRoboto(
          SonusThemeFactory.build(const SonusAppearanceSpec()),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MomentFeedCard(
              story: story,
              now: _day.add(const Duration(days: 1)),
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder key(String part, MomentStory story) =>
      find.byKey(ValueKey<String>('moment-post-$part-${story.id}'));

  testWidgets('a short headline keeps the words beside the picture', (
    tester,
  ) async {
    final story = _compose([_rise(_short, from: 18, to: 16)]).single;
    await pump(tester, story);

    expect(key('layout-side', story), findsOneWidget);
    final media = tester.getRect(key('media', story));
    final headline = tester.getRect(key('headline', story));
    expect(headline.left, greaterThan(media.right));
    expect(headline.top, lessThan(media.bottom));
    // At most four headline lines beside the picture.
    final lineHeight = 16 * 1.28;
    expect(
      tester.getSize(key('headline', story)).height,
      lessThanOrEqualTo(lineHeight * MomentBulletinCard.maxSideLines + 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long headline flows beneath the picture, full width', (
    tester,
  ) async {
    final story = _compose([_rise(_long, from: 51, to: 9)]).single;
    expect(story.isDeveloping, isFalse);
    await pump(tester, story);

    expect(key('layout-flow', story), findsOneWidget);
    final card = tester.getRect(key('layout-flow', story));
    final media = tester.getRect(key('media', story));
    final headline = tester.getRect(key('headline', story));
    final badges = tester.getRect(key('badges', story));
    expect(headline.top, greaterThanOrEqualTo(media.bottom));
    expect(headline.width, greaterThan(card.width * 0.85));
    // The badges and byline use the room beside the picture.
    expect(badges.left, greaterThan(media.right));
    expect(badges.bottom, lessThanOrEqualTo(media.bottom + 1));
    // Nothing is cut: the whole headline is shown.
    expect(find.text(story.headline), findsOneWidget);
    expect(tester.widget<Text>(key('headline', story)).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an update thread flows beneath the picture and still opens', (
    tester,
  ) async {
    final stories = _compose([
      _rise(_long, from: 51, to: 30, hour: 9),
      _rise(_long, from: 30, to: 15, hour: 12),
      _rise(_long, from: 15, to: 9, hour: 15),
    ]);
    final story = stories.firstWhere((s) => s.isDeveloping);
    await pump(tester, story);

    expect(key('layout-flow', story), findsOneWidget);
    expect(key('updated', story), findsOneWidget);
    final media = tester.getRect(key('media', story));
    expect(
      tester.getRect(key('headline', story)).top,
      greaterThanOrEqualTo(media.bottom),
    );
    await tester.tap(key('thread', story));
    await tester.pump();
    for (final update in story.updates) {
      expect(find.text(update.text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('large text ($scale x) stacks the picture above the words', (
      tester,
    ) async {
      for (final story in [
        _compose([_rise(_short, from: 18, to: 16)]).single,
        _compose([_rise(_long, from: 51, to: 9)]).single,
      ]) {
        await pump(tester, story, textScale: scale);
        expect(key('layout-stacked', story), findsOneWidget);
        expect(find.text(story.headline), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('a 320dp phone lays out every case without overflow', (
    tester,
  ) async {
    for (final story in [
      _compose([_rise(_short, from: 18, to: 16)]).single,
      _compose([_rise(_long, from: 51, to: 9)]).single,
    ]) {
      await pump(tester, story, width: 320);
      expect(tester.getRect(find.byType(MomentFeedCard)).right, 300);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an archived weekly story keeps its words and lays out', (
    tester,
  ) async {
    final story = _compose([
      _rise(
        _short,
        from: 12,
        to: 7,
        scope: ChartMomentScope.finalized,
        type: ChartMomentEventType.newPeak,
      ),
    ]).single;
    expect(story.item.scope, ChartMomentScope.finalized);
    await pump(tester, story);

    expect(find.text(story.headline), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'moment-post-layout-',
            ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
