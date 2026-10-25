// Player-1: the mini-player lived in the shell's bottom bar, so most pushed
// pages (albums, artists, Studios, Settings, Import) had no playback
// controls. One host now places it below every route.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
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
}
