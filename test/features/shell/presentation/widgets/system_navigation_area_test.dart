// App Update 1.3 preview: on the Galaxy S26 Ultra the mini-player was drawn
// behind Android's three navigation buttons, with no Sonus background under
// them. The intended bottom of the screen, top to bottom: the page, the
// whole mini-player, then an opaque Sonus-coloured area the size of the
// system navigation inset, under Android's own buttons (Android 15+ ignores
// the navigation bar colour an app asks for, so Sonus paints it).
//
// Cause: the device can keep reporting a keyboard inset after the keyboard
// is gone. Flutter derives `padding` as `viewPadding - viewInsets`, so the
// navigation inset read as 0; KeyboardInsetGuard dropped the stale keyboard
// inset but left that zeroed padding, and the shell laid the bar out as if
// there were no navigation bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/presentation/widgets/keyboard_inset_guard.dart';
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

const double _height = 800;
const double _ratio = 3;

void main() {
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late PlaybackStateController stateController;

  setUp(() {
    engine = JustAudioPlaybackEngine(
      audioPlayer: SimulatedJustAudioPlayer(),
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);
    stateController = PlaybackStateController(coordinator: coordinator);
  });

  tearDown(() async {
    stateController.dispose();
    await engine.dispose();
  });

  final bar = find.byKey(const ValueKey<String>('playback-host-bar'));
  final card = find.byKey(const ValueKey<String>('mini-player'));
  final inset = find.byKey(
    const ValueKey<String>('playback-host-system-inset'),
  );

  /// Android's report: a navigation bar of [navigationDp], and a keyboard
  /// inset of [keyboardDp] (stale when no field is being edited). Flutter's
  /// `padding` is what is left of the first after the second.
  void report(
    WidgetTester tester, {
    double navigationDp = 48,
    double keyboardDp = 0,
  }) {
    tester.view.viewPadding = FakeViewPadding(bottom: navigationDp * _ratio);
    final left = (navigationDp - keyboardDp).clamp(0, double.infinity);
    tester.view.padding = FakeViewPadding(bottom: left * _ratio);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardDp * _ratio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool playing = true,
    Widget home = const Scaffold(body: Center(child: Text('Moments'))),
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, _height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigatorKey = GlobalKey<NavigatorState>();
    final routes = PlaybackHostRouteObserver();
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
          // The app's own order (SonusApp): the guard around the host.
          builder: (context, navigator) => KeyboardInsetGuard(
            child: PlaybackHost(
              navigatorKey: navigatorKey,
              routes: routes,
              child: navigator!,
            ),
          ),
          home: home,
        ),
      ),
    );
    if (playing) {
      await tester.runAsync(() async {
        await engine.loadQueue([_track], autoPlay: false);
        await Future<void>.delayed(Duration.zero);
      });
    }
    await tester.pump();
  }

  /// The whole mini-player above the navigation area, with an opaque
  /// Sonus background from its bottom to the bottom of the screen.
  void expectSeparated(WidgetTester tester, double navigationDp) {
    final cardRect = tester.getRect(card);
    expect(cardRect.bottom, lessThanOrEqualTo(_height - navigationDp + 0.5));
    // No extra gap: the card ends at the navigation area (or its 8 dp
    // margin without one).
    expect(
      cardRect.bottom,
      greaterThanOrEqualTo(_height - navigationDp - 8 - 0.5),
    );
    final progress = tester.getRect(
      find.byKey(const ValueKey<String>('mini-player-progress')),
    );
    expect(progress.bottom, lessThanOrEqualTo(_height - navigationDp + 0.5));

    // The bar's surface reaches the bottom of the screen and is opaque, so
    // nothing shows behind Android's buttons.
    final barRect = tester.getRect(bar);
    expect(barRect.bottom, closeTo(_height, 0.5));
    final surface = tester.widget<Material>(
      find.descendant(of: bar, matching: find.byType(Material)).first,
    );
    expect(surface.color, isNotNull);
    expect(surface.color!.a, 1.0);
  }

  testWidgets('a stale keyboard inset with no field open: the mini-player '
      'stays above the three-button bar, on an opaque Sonus background', (
    tester,
  ) async {
    report(tester, keyboardDp: 300);
    await pump(tester);

    expect(card, findsOneWidget);
    expectSeparated(tester, 48);
  });

  testWidgets('the same on gesture navigation', (tester) async {
    report(tester, navigationDp: 16, keyboardDp: 300);
    await pump(tester);

    expectSeparated(tester, 16);
  });

  testWidgets('a stale keyboard inset smaller than the navigation bar', (
    tester,
  ) async {
    report(tester, keyboardDp: 20);
    await pump(tester);

    expectSeparated(tester, 48);
  });

  testWidgets('no song loaded: the navigation area is still painted at its '
      'full size', (tester) async {
    report(tester, keyboardDp: 300);
    await pump(tester, playing: false);

    expect(tester.getSize(inset).height, closeTo(48, 0.5));
    expect(tester.getRect(inset).bottom, closeTo(_height, 0.5));
    final box = tester.widget<ColoredBox>(inset);
    expect(box.color.a, 1.0);
  });

  testWidgets('a keyboard really open for a field: the bar steps aside and '
      'no navigation space is added above the keyboard', (tester) async {
    report(tester, keyboardDp: 300);
    await pump(
      tester,
      home: const Scaffold(body: Center(child: TextField(autofocus: true))),
    );
    await tester.pump();

    expect(bar, findsNothing);
    expect(inset, findsNothing);
  });

  testWidgets('normal reports stay as they were: 48 dp and no keyboard', (
    tester,
  ) async {
    report(tester);
    await pump(tester);

    expectSeparated(tester, 48);
  });
}
