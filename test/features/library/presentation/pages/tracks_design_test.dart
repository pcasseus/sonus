import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

import 'tracks_page_test.dart' as base;

// SN-48H: Tracks presentation. Fictional fixtures only.
void main() {
  List<LibraryTrack> tracks() => [
    base.createTrack(
      songId: 'long',
      title: 'An Exceptionally Long Fixture Song Title That Has To Wrap',
      artistName: 'The Extraordinarily Long Fixture Ensemble',
      albumTitle: 'A Remarkably Long Fixture Album Title (Deluxe Edition)',
      featuredArtists: const ['Guest Fixture'],
      durationSeconds: 3725,
    ),
    base.createTrack(songId: 'short', title: 'Short', durationSeconds: 61),
    base.createTrack(
      songId: 'blocked',
      title: 'Blocked Fixture',
      isSongBlocked: true,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
    PlaybackEngine? engine,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      base.buildSubject(
        repository: base.FakeLibraryQueryRepository(tracks: tracks()),
        engine: engine,
        theme: SonusThemeFactory.build(spec),
        appBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
      await pump(
        tester,
        spec: SonusAppearanceSpec(themeId: id),
        size: const Size(320, 3000),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      // Large text moves the duration into the supporting line.
      expect(find.textContaining('1:02:05'), findsOneWidget);
    });
  }

  for (final level in SonusDecorationIntensity.values) {
    testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
      await pump(tester, spec: SonusAppearanceSpec(decoration: level));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('durations use tabular figures', (tester) async {
    await pump(tester);

    final duration = tester.widget<Text>(
      find.byKey(const ValueKey<String>('track-duration-short')),
    );
    expect(duration.data, '1:01');
    expect(
      duration.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('wide screens keep sort beside the playback buttons', (
    tester,
  ) async {
    await pump(tester, size: const Size(900, 900));

    final play = tester.getRect(
      find.byKey(const ValueKey<String>('tracks-play-all-button')),
    );
    final sort = tester.getRect(
      find.byKey(const ValueKey<String>('tracks-order-dropdown')),
    );
    expect(sort.center.dy, closeTo(play.center.dy, 12));
  });

  testWidgets('marks the song now playing, from the player state', (
    tester,
  ) async {
    final engine = _NowPlayingEngine();
    addTearDown(engine.close);
    await pump(tester, engine: engine);

    expect(find.bySemanticsLabel(RegExp('Now playing')), findsNothing);

    engine.playing('short');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Now playing')), findsOneWidget);
  });
}

/// Reports a current song, like the real engine's state stream.
class _NowPlayingEngine implements PlaybackEngine {
  final _states = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  void playing(String songId) {
    _state = PlaybackState(
      queue: PlaybackQueue(
        tracks: [
          PlaybackTrack(
            songId: songId,
            title: 'Fixture',
            artistId: 'artist-1',
            artistName: 'Artist',
            albumId: 'album-1',
            albumTitle: 'Album',
            filePath: '/music/$songId.mp3',
            duration: const Duration(minutes: 1),
          ),
        ],
        currentIndex: 0,
      ),
    );
    _states.add(_state);
  }

  Future<void> close() => _states.close();

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  PlaybackState get currentState => _state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
