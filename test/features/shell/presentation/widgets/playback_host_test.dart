// Player-1: the mini-player lived in the shell's bottom bar, so most pushed
// pages (albums, artists, Studios, Settings, Import) had no playback
// controls. One host now places it below every route.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/player/presentation/pages/now_playing_page.dart';
import 'package:sonus_next/features/player/presentation/pages/playback_queue_page.dart';
import 'package:sonus_next/features/shell/presentation/widgets/playback_host.dart';

import '../../../player/data/engines/simulated_just_audio_player.dart';

const _track = PlaybackTrack(
  songId: 'song-1',
  title: 'Song One',
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  filePath: '/music/one.mp3',
  duration: Duration(minutes: 3),
);

void main() {
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late PlaybackStateController stateController;
  late GlobalKey<NavigatorState> navigatorKey;
  late PlaybackHostRouteObserver hostRoutes;

  setUp(() {
    engine = JustAudioPlaybackEngine(
      audioPlayer: SimulatedJustAudioPlayer(),
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
    stateController = PlaybackStateController(coordinator: coordinator);
    navigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() async {
    stateController.dispose();
    await engine.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final routes = hostRoutes = PlaybackHostRouteObserver();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaybackCoordinator>.value(value: coordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(
            value: stateController,
          ),
          ChangeNotifierProvider<LyricsController?>.value(value: null),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routes],
          builder: (context, navigator) => PlaybackHost(
            navigatorKey: navigatorKey,
            routes: routes,
            child: navigator!,
          ),
          home: const Scaffold(body: Center(child: Text('Home'))),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> startPlaying(WidgetTester tester) async {
    await tester.runAsync(() async {
      await engine.loadQueue([_track], autoPlay: false);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> pushPage(WidgetTester tester, String name) async {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(name)),
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Text('$name bottom', key: ValueKey<String>(name)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final bar = find.byKey(const ValueKey<String>('playback-host-bar'));
  final miniPlayer = find.byKey(const ValueKey<String>('mini-player'));

  testWidgets('no bar while nothing is queued', (tester) async {
    await pumpApp(tester);

    expect(bar, findsNothing);
  });

  testWidgets('one bar on the shell and on every pushed page', (tester) async {
    await pumpApp(tester);
    await startPlaying(tester);

    expect(miniPlayer, findsOneWidget);

    for (final page in ['Album', 'Artist', 'Album Studio', 'Settings']) {
      await pushPage(tester, page);

      expect(miniPlayer, findsOneWidget, reason: page);

      // The page ends where the bar begins: nothing is covered.
      final pageBottom = tester.getBottomLeft(find.byKey(ValueKey(page))).dy;
      expect(pageBottom, lessThanOrEqualTo(tester.getTopLeft(bar).dy));
    }
  });

  testWidgets('hidden on Now Playing, back when it closes', (tester) async {
    await pumpApp(tester);
    await startPlaying(tester);

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('now-playing-seek')),
      findsOneWidget,
    );
    expect(bar, findsNothing, reason: 'Now Playing has its own controls');

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(miniPlayer, findsOneWidget);
  });

  testWidgets('Queue opens from the bar and keeps the bar', (tester) async {
    await pumpApp(tester);
    await startPlaying(tester);

    await tester.tap(find.byKey(const ValueKey<String>('mini-player-queue')));
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackQueuePage), findsOneWidget);
    expect(miniPlayer, findsOneWidget);
  });

  testWidgets('steps aside while the keyboard is open', (tester) async {
    await pumpApp(tester);
    await startPlaying(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(bar, findsNothing);

    tester.view.resetViewInsets();
    await tester.pump();

    expect(miniPlayer, findsOneWidget);
  });

  testWidgets('controls work from a pushed page', (tester) async {
    await pumpApp(tester);
    await startPlaying(tester);
    await pushPage(tester, 'Album');

    await tester.tap(
      find.byKey(const ValueKey<String>('mini-player-play-pause')),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(stateController.state.isPlaying, isTrue);
  });

  group('SN-45 mini-player and Now Playing', () {
    final nowPlaying = find.byType(NowPlayingPage);

    testWidgets('an upward swipe on the bar opens Now Playing', (tester) async {
      await pumpApp(tester);
      await startPlaying(tester);

      await tester.fling(miniPlayer, const Offset(0, -200), 1000);
      await tester.pumpAndSettle();

      expect(nowPlaying, findsOneWidget);
    });

    testWidgets('tapping twice still opens one Now Playing', (tester) async {
      await pumpApp(tester);
      await startPlaying(tester);
      final open = find.byKey(const ValueKey<String>('mini-player-open'));

      final seen = <double>[];
      hostRoutes.nowPlayingCoverage.addListener(
        () => seen.add(hostRoutes.nowPlayingCoverage.value),
      );
      await tester.tap(open);
      await tester.pump();
      // The bar never vanishes for a frame when Now Playing is pushed.
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(open, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(nowPlaying, findsOneWidget);
      // Coverage only ever grows while opening: no flicker back to 0.
      expect(seen.first, lessThan(0.5));
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(nowPlaying, findsNothing, reason: 'one pop closes it');
      expect(miniPlayer, findsOneWidget);
    });

    testWidgets('the bar folds away while Now Playing rises, no jump', (
      tester,
    ) async {
      await pumpApp(tester);
      await startPlaying(tester);
      final barTop = tester.getTopLeft(bar).dy;

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Part way: the bar is still there, partly folded.
      expect(bar, findsOneWidget);
      final folding = tester.getTopLeft(bar).dy;
      expect(folding, greaterThan(barTop));
      expect(folding, lessThan(800));

      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      // And it unfolds again as Now Playing closes.
      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(bar, findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(bar).dy, barTop);
    });

    testWidgets('with reduced motion the bar folds away at once', (
      tester,
    ) async {
      await pumpApp(tester);
      await startPlaying(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pump();
      await tester.pump();

      expect(nowPlaying, findsOneWidget);
      expect(bar, findsNothing);
    });

    testWidgets('a sideways swipe closes the player while paused', (
      tester,
    ) async {
      await pumpApp(tester);
      await startPlaying(tester);
      expect(stateController.state.isPlaying, isFalse);

      await tester.drag(miniPlayer, const Offset(-320, 0));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(stateController.state.queue.isEmpty, isTrue);
      expect(bar, findsNothing);
    });

    testWidgets('a sideways swipe never stops music that is playing', (
      tester,
    ) async {
      await pumpApp(tester);
      await startPlaying(tester);
      await tester.runAsync(() async {
        await coordinator.play();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(stateController.state.isPlaying, isTrue);

      await tester.drag(miniPlayer, const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(stateController.state.isPlaying, isTrue);
      expect(stateController.state.queue.isNotEmpty, isTrue);
      expect(miniPlayer, findsOneWidget);
      // It springs back into place.
      expect(tester.getTopLeft(miniPlayer).dx, closeTo(8, 0.5));
    });

    testWidgets('closing is also a screen-reader action, only while paused', (
      tester,
    ) async {
      await pumpApp(tester);
      await startPlaying(tester);

      Set<String?> actions() => {
        for (final action
            in tester
                    .widget<Semantics>(
                      find.byWidgetPredicate(
                        (w) =>
                            w is Semantics &&
                            w.properties.label == 'Now playing',
                      ),
                    )
                    .properties
                    .customSemanticsActions
                    ?.keys ??
                const <CustomSemanticsAction>[])
          action.label,
      };

      expect(actions(), {'Open Now Playing', 'Close player'});

      await tester.runAsync(() async {
        await coordinator.play();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(actions(), {'Open Now Playing'});
    });

    testWidgets('the navigation area is reserved and painted, never content', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(bottom: 144);
      addTearDown(tester.view.resetPadding);
      await pumpApp(tester);

      final inset = find.byKey(
        const ValueKey<String>('playback-host-system-inset'),
      );
      expect(inset, findsOneWidget);
      final insetTop = tester.getTopLeft(inset).dy;
      expect(tester.getSize(inset).height, closeTo(48, 0.5));

      await pushPage(tester, 'Album');
      final pageBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('Album')))
          .dy;
      expect(pageBottom, lessThanOrEqualTo(insetTop));

      // With music queued, the bar takes the area instead.
      await startPlaying(tester);
      expect(inset, findsNothing);
      expect(bar, findsOneWidget);
    });
  });

  // App Update 1.3 preview report: the mini-player looked partly hidden by
  // the navigation area. These pin that the whole bar stays above the
  // system's bottom inset, on gesture and three-button navigation, without
  // counting the inset twice or adding space below it.
  group('the whole bar stays above the system navigation area', () {
    const screenHeight = 800.0;
    // The test view's density: physical pixels per logical pixel.
    const ratio = 3.0;

    void setNavigation(WidgetTester tester, double insetDp) {
      final inset = FakeViewPadding(bottom: insetDp * ratio);
      tester.view.padding = inset;
      tester.view.viewPadding = inset;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
    }

    Future<void> playTitled(WidgetTester tester, String title) async {
      await tester.runAsync(() async {
        await engine.loadQueue([
          PlaybackTrack(
            songId: 'song-long',
            title: title,
            artistId: 'artist',
            artistName: 'An Artist With A Long Name Too',
            albumId: 'album',
            albumTitle: 'Album',
            filePath: '/music/long.mp3',
            duration: const Duration(minutes: 3),
          ),
        ], autoPlay: false);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }

    Rect card(WidgetTester tester) => tester.getRect(miniPlayer);

    /// Every part of the bar is above the inset; the inset is applied once
    /// (no gap of a second inset) and no more than the 8 dp margin is
    /// added below.
    void expectAboveInset(WidgetTester tester, double insetDp) {
      final limit = screenHeight - insetDp;
      final rect = card(tester);
      expect(rect.bottom, lessThanOrEqualTo(limit + 0.5));
      expect(rect.bottom, lessThanOrEqualTo(screenHeight - 8 + 0.5));
      expect(rect.bottom, greaterThanOrEqualTo(limit - 8 - 0.5));
      for (final part in [
        'mini-player-artwork',
        'mini-player-title',
        'mini-player-artist',
        'mini-player-play-pause',
        'mini-player-next',
        'mini-player-progress',
      ]) {
        final finder = find.byKey(ValueKey<String>(part));
        if (finder.evaluate().isEmpty) continue;
        final partRect = tester.getRect(finder);
        expect(partRect.bottom, lessThanOrEqualTo(limit + 0.5), reason: part);
        expect(
          partRect.top,
          greaterThanOrEqualTo(rect.top - 0.5),
          reason: part,
        );
      }
    }

    for (final (name, insetDp) in [
      ('three-button navigation (48 dp)', 48.0),
      ('gesture navigation (16 dp)', 16.0),
      ('no navigation inset', 0.0),
    ]) {
      testWidgets(name, (tester) async {
        setNavigation(tester, insetDp);
        await pumpApp(tester);
        await startPlaying(tester);

        expectAboveInset(tester, insetDp);
        expect(tester.getRect(bar).bottom, closeTo(screenHeight, 0.5));
      });
    }

    testWidgets('a long title at 2x text on three-button navigation', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      setNavigation(tester, 48);
      await pumpApp(tester);
      await playTitled(
        tester,
        'A very long song title that cannot possibly fit on the bar',
      );

      expect(tester.takeException(), isNull);
      expectAboveInset(tester, 48);
    });

    testWidgets('keyboard open hides the bar; closed, it returns to the '
        'same place', (tester) async {
      setNavigation(tester, 48);
      await pumpApp(tester);
      await startPlaying(tester);
      final before = card(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * ratio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(bar, findsNothing);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(card(tester), before);
    });

    testWidgets('pushing a page, returning, and opening and closing Now '
        'Playing leave the bar where it was', (tester) async {
      setNavigation(tester, 16);
      await pumpApp(tester);
      await startPlaying(tester);
      final before = card(tester);

      await pushPage(tester, 'Artist Profile');
      expect(card(tester), before);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(card(tester), before);

      await tester.tap(find.byKey(const ValueKey<String>('mini-player-open')));
      await tester.pumpAndSettle();
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(card(tester), before);
      expectAboveInset(tester, 16);
    });

    testWidgets('the end of a long page scrolls into view above the bar', (
      tester,
    ) async {
      setNavigation(tester, 48);
      await pumpApp(tester);
      await startPlaying(tester);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(
                    height: 56,
                    child: Text('Row $i', key: ValueKey<String>('row-$i')),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('row-59')));
      expect(last.bottom, lessThanOrEqualTo(tester.getRect(bar).top + 0.5));
    });

    testWidgets('without a player, pages end at the gesture inset', (
      tester,
    ) async {
      setNavigation(tester, 16);
      await pumpApp(tester);
      final inset = find.byKey(
        const ValueKey<String>('playback-host-system-inset'),
      );
      expect(tester.getSize(inset).height, closeTo(16, 0.5));
      await pushPage(tester, 'Moments');
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('Moments'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(inset).dy + 0.5),
      );
    });
  });
}
