import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/widgets/playback/sonus_mini_player.dart';

// Universal mini-player surface (SN-48 mini-player design). Fictional values.
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

  group('SonusMiniPlayer', () {
    Widget mini({
      VoidCallback? onPlay,
      VoidCallback? onNext,
      VoidCallback? onOpen,
    }) => Align(
      alignment: Alignment.bottomCenter,
      child: SonusMiniPlayer(
        title: 'An Exceptionally Long Fixture Song Title',
        artist: 'The Extraordinarily Long Fixture Ensemble',
        artworkPath: '/art/cover.png',
        isPlaying: false,
        progress: 0.4,
        onPlayPause: onPlay,
        onNext: onNext,
        onOpen: onOpen,
      ),
    );

    testWidgets('play, next and open each work', (tester) async {
      final calls = <String>[];
      await pump(
        tester,
        mini(
          onPlay: () => calls.add('play'),
          onNext: () => calls.add('next'),
          onOpen: () => calls.add('open'),
        ),
      );

      await tester.tap(find.byTooltip('Play'));
      await tester.tap(find.byTooltip('Next'));
      await tester.tap(find.text('An Exceptionally Long Fixture Song Title'));
      expect(calls, ['play', 'next', 'open']);
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} fits 320dp at 2x text', (tester) async {
        await pump(
          tester,
          mini(onPlay: () {}),
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 400),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        final bar = tester.getSize(
          find.byKey(const ValueKey<String>('sonus-mini-player')),
        );
        expect(bar.height, greaterThanOrEqualTo(SonusMiniPlayer.height));
      });
    }

    testWidgets('pages can reserve exactly its space', (tester) async {
      late double reserved;
      await pump(
        tester,
        Builder(
          builder: (context) {
            reserved = SonusMiniPlayer.reservedHeight(context);
            return const SizedBox();
          },
        ),
      );

      expect(reserved, SonusMiniPlayer.height + 16);
    });
  });
}
