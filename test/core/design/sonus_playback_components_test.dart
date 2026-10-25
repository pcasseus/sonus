import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_definition.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_lyrics_view.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_now_playing_view.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_playback_controls.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_playback_progress.dart';

// SN-48E: playback presentation components. Fictional values only.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(spec),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  const minute = Duration(minutes: 4);

  group('SonusPlaybackProgress', () {
    Widget progress({
      Duration position = const Duration(minutes: 1),
      Duration? duration = minute,
      ValueChanged<Duration>? onSeek,
      SonusProgressStyle? style,
    }) => Padding(
      padding: const EdgeInsets.all(20),
      child: SonusPlaybackProgress(
        position: position,
        duration: duration,
        onSeek: onSeek,
        style: style,
      ),
    );

    Finder track() => find.byType(CustomPaint).last;

    testWidgets('tapping seeks to that point of the song', (tester) async {
      Duration? sought;
      await pump(tester, progress(onSeek: (value) => sought = value));

      final rect = tester.getRect(track());
      await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));

      expect(
        sought!.inMilliseconds,
        closeTo(minute.inMilliseconds * 0.75, 2000),
      );
    });

    testWidgets('dragging previews, then seeks once on release', (
      tester,
    ) async {
      final sought = <Duration>[];
      await pump(tester, progress(onSeek: sought.add));

      final rect = tester.getRect(track());
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.2, rect.center.dy),
      );
      await gesture.moveBy(Offset(rect.width * 0.3, 0));
      await tester.pump();
      expect(sought, isEmpty);
      await gesture.up();

      expect(sought, hasLength(1));
      expect(
        sought.single.inMilliseconds,
        closeTo(minute.inMilliseconds * 0.5, 4000),
      );
    });

    testWidgets('arrow keys step by five seconds', (tester) async {
      Duration? sought;
      await pump(tester, progress(onSeek: (value) => sought = value));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

      expect(sought, const Duration(minutes: 1, seconds: 5));
    });

    testWidgets('screen readers get a slider with step actions', (
      tester,
    ) async {
      Duration? sought;
      final handle = tester.ensureSemantics();
      await pump(tester, progress(onSeek: (value) => sought = value));

      final node = tester.getSemantics(find.byType(SonusPlaybackProgress));
      expect(node.flagsCollection.isSlider, isTrue);
      expect(node.value, '1 minute 0 seconds of 4 minutes 0 seconds');

      tester.semantics.decrease(find.semantics.byLabel('Playback position'));
      expect(sought, const Duration(seconds: 55));
      handle.dispose();
    });

    testWidgets('unknown length reads --:-- and cannot seek', (tester) async {
      var seeks = 0;
      await pump(tester, progress(duration: null, onSeek: (_) => seeks++));

      expect(find.text('--:--'), findsOneWidget);
      await tester.tap(track());
      expect(seeks, 0);
    });

    testWidgets('never animates by itself', (tester) async {
      await pump(tester, progress());
      await tester.pump(const Duration(seconds: 1));

      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    test('equal inputs never repaint', () {
      const painter = SonusProgressPainter(
        style: SonusProgressStyle.sprayWave,
        fraction: 0.4,
        active: Colors.red,
        inactive: Colors.grey,
        thumb: Colors.red,
        gradients: true,
        known: true,
      );
      expect(painter.shouldRepaint(painter), isFalse);
    });

    for (final style in SonusProgressStyle.values) {
      testWidgets('${style.name} paints at 320dp and 2x', (tester) async {
        await pump(
          tester,
          progress(style: style, onSeek: (_) {}),
          size: const Size(320, 400),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('follows the theme treatment by default', (tester) async {
      await pump(
        tester,
        progress(),
        spec: const SonusAppearanceSpec(themeId: SonusThemeId.kickflip),
      );

      final paint = tester.widget<CustomPaint>(track());
      expect(
        (paint.painter! as SonusProgressPainter).style,
        SonusProgressStyle.tapeStrip,
      );
    });
  });

  group('SonusPlaybackControls', () {
    testWidgets('each button runs its action and says what it does', (
      tester,
    ) async {
      final calls = <String>[];
      await pump(
        tester,
        SonusPlaybackControls(
          isPlaying: true,
          shuffleEnabled: true,
          repeat: SonusRepeatDisplay.one,
          onPlayPause: () => calls.add('play'),
          onPrevious: () => calls.add('previous'),
          onNext: () => calls.add('next'),
          onToggleShuffle: () => calls.add('shuffle'),
          onCycleRepeat: () => calls.add('repeat'),
        ),
      );

      for (final tooltip in [
        'Pause',
        'Previous',
        'Next',
        'Shuffle on',
        'Repeat one',
      ]) {
        await tester.tap(find.byTooltip(tooltip));
      }
      expect(calls, ['play', 'previous', 'next', 'shuffle', 'repeat']);
    });

    testWidgets('loading disables play and shows progress', (tester) async {
      await pump(
        tester,
        SonusPlaybackControls(
          isPlaying: false,
          isLoading: true,
          onPlayPause: () {},
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('sonus-play-pause-button')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('SonusNowPlayingView', () {
    Widget view({VoidCallback? onQueue, VoidCallback? onLyrics}) =>
        SonusNowPlayingView(
          title: 'An Exceptionally Long Fixture Song Title That Has To Wrap',
          artist: 'The Extraordinarily Long Fixture Ensemble',
          album: 'Fixture Album (Deluxe Edition)',
          artworkPath: '/art/cover.png',
          artworkPalette: _FakePalette(),
          position: const Duration(minutes: 1),
          duration: minute,
          isPlaying: true,
          onSeek: (_) {},
          onPlayPause: () {},
          onPrevious: () {},
          onNext: () {},
          onOpenQueue: onQueue,
          onOpenLyrics: onLyrics,
        );

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          view(),
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 700),
          textScale: 2,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    for (final level in SonusDecorationIntensity.values) {
      testWidgets('Decoration ${level.label} renders cleanly', (tester) async {
        await pump(
          tester,
          view(),
          spec: SonusAppearanceSpec(decoration: level),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('queue and lyrics open from the view', (tester) async {
      final opened = <String>[];
      await pump(
        tester,
        view(
          onQueue: () => opened.add('queue'),
          onLyrics: () => opened.add('lyrics'),
        ),
        size: const Size(411, 1400),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('sonus-now-playing-queue')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('sonus-now-playing-lyrics')),
      );
      expect(opened, ['queue', 'lyrics']);
    });

    testWidgets('wide screens place the artwork beside the controls', (
      tester,
    ) async {
      await pump(tester, view(), size: const Size(1000, 600));
      await tester.pumpAndSettle();

      final art = tester.getRect(find.byType(Image).first);
      final title = tester.getRect(
        find.byKey(const ValueKey<String>('sonus-now-playing-title')),
      );
      expect(title.left, greaterThan(art.right));
    });
  });

  group('SonusLyricsView', () {
    final synced = [
      for (var i = 0; i < 30; i++)
        SonusLyricLine(
          text: 'Fixture line $i',
          start: Duration(seconds: i * 4),
        ),
    ];

    testWidgets('highlights the line now playing', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        SonusLyricsView(lines: synced, position: const Duration(seconds: 9)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.text('Fixture line 2'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.text('Fixture line 1'))
            .flagsCollection
            .isSelected,
        isNot(Tristate.isTrue),
      );
      handle.dispose();
    });

    testWidgets('tapping a line seeks to its time', (tester) async {
      Duration? sought;
      await pump(
        tester,
        SonusLyricsView(
          lines: synced,
          position: Duration.zero,
          onSeek: (value) => sought = value,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fixture line 3'));
      expect(sought, const Duration(seconds: 12));
    });

    testWidgets('scrolling by hand pauses following until resumed', (
      tester,
    ) async {
      await pump(
        tester,
        SonusLyricsView(lines: synced, position: Duration.zero),
        size: const Size(411, 600),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('sonus-lyrics-resume')),
        findsNothing,
      );

      await tester.drag(find.text('Fixture line 2'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('sonus-lyrics-resume')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('sonus-lyrics-resume')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('sonus-lyrics-resume')),
        findsNothing,
      );
    });

    testWidgets('unsynchronised lyrics show plainly, missing ones explain', (
      tester,
    ) async {
      await pump(
        tester,
        const SonusLyricsView(
          lines: [SonusLyricLine(text: 'Plain fixture line')],
          position: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plain fixture line'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('sonus-lyrics-resume')),
        findsNothing,
      );

      await pump(
        tester,
        const SonusLyricsView(lines: [], position: Duration.zero),
      );
      expect(find.text('No lyrics for this song'), findsOneWidget);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      await pump(
        tester,
        SonusLyricsView(lines: synced, position: const Duration(seconds: 30)),
        size: const Size(320, 600),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

class _FakePalette extends SonusArtworkPalette {
  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async => const SonusArtworkColors(
    accent: Color(0xFFFF8A80),
    container: Color(0xFF8C1D18),
  );
}
