// SN-49: what a screen reader finds in a Moment. The headline and body
// are in the semantics tree, read together with the byline; each story is
// its own container; buttons say what they open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/news/moment_post_card.dart';

import '../editorial/moment_editorial_test.dart' as fixtures;

void main() {
  List<MomentStory> stories() =>
      MomentEditorialDesk(
        lookups: fixtures.FakeLookups(
          artists: {'artist-a': 'Name artist-a', 'artist-b': 'Name artist-b'},
        ),
        minorStoriesPerDay: 100,
      ).compose(
        fixtures.items([
          fixtures.event(
            ChartMomentEventType.firstNumberOne,
            entity: fixtures.song('s1'),
            rank: 1,
            threshold: 1,
            streams: 30,
            source: 'p1',
          ),
          fixtures.event(
            ChartMomentEventType.debut,
            entity: fixtures.song('s2', artist: 'artist-b'),
            rank: 5,
            streams: 40,
            source: 'p2',
            at: DateTime.utc(2026, 10, 26, 13),
          ),
        ]),
      );

  Future<List<MomentStory>> pump(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    final feed = stories();
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final story in feed)
                  MomentPostCard(
                    story: story,
                    now: DateTime.utc(2026, 10, 27),
                    onOpenSong: () {},
                    onOpenAlbum: () {},
                    onOpenArtist: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return feed;
  }

  testWidgets('each story is one container; its byline, headline and body '
      'are read as one item', (tester) async {
    final handle = tester.ensureSemantics();
    final feed = await pump(tester);

    for (final story in feed) {
      final text = tester
          .getSemantics(find.byKey(ValueKey('moment-post-story-${story.id}')))
          .getSemanticsData()
          .label;
      expect(text, contains(story.publisher.label));
      expect(text, contains(story.headline));
      expect(text, contains(story.body!));
      expect(
        text.indexOf(story.headline),
        lessThan(text.indexOf(story.body!)),
        reason: 'read in the order shown',
      );

      final container = tester.getSemantics(
        find.byKey(ValueKey('moment-post-${story.id}')),
      );
      expect(
        container.getSemanticsData().label,
        isEmpty,
        reason: 'the container groups the story; it is not read itself',
      );
    }
    handle.dispose();
  });

  testWidgets('buttons say which song, release or artist they open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel('Open artist, Name artist-a'), findsOneWidget);
    expect(find.bySemanticsLabel('Open artist, Name artist-b'), findsOneWidget);
    expect(find.bySemanticsLabel('Song options, Song s1'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Album, Album of s2'), findsOneWidget);
    // The visible words stay short.
    expect(find.text('Artist'), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('fits 320dp at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
