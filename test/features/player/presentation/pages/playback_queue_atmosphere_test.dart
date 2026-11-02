import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/player/presentation/pages/playback_queue_page.dart';

import '../../../shell/presentation/widgets/shell_playback_slot_test.dart'
    as shell;

// SN-50 D-Q18: the Queue screen carries a subtle wash of the current
// song's artwork behind the list, and stays flat when decoration is
// limited. Fictional values only.
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

const _current = PlaybackTrack(
  songId: 'song-1',
  title: 'Paper Lanterns',
  artistId: 'artist-1',
  artistName: 'Harbor Lights',
  albumId: 'album-1',
  albumTitle: 'Tidewater',
  filePath: '/music/paper-lanterns.mp3',
  artworkPath: '/covers/tidewater.jpg',
  duration: Duration(minutes: 3),
);

void main() {
  Future<shell.FakePlaybackEngine> pump(
    WidgetTester tester, {
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 900),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = shell.FakePlaybackEngine(
      initialState: const PlaybackState(
        queue: PlaybackQueue(
          tracks: [_current, shell.track2, shell.track3],
          currentIndex: 0,
        ),
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 3),
      ),
    );
    addTearDown(engine.dispose);
    final coordinator = PlaybackCoordinator(engine: engine);
    final state = PlaybackStateController(coordinator: coordinator);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PlaybackCoordinator>.value(value: coordinator),
          ChangeNotifierProvider<PlaybackStateController>.value(value: state),
        ],
        child: MaterialApp(
          theme: SonusThemeFactory.build(spec),
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: PlaybackQueuePage(artworkPalette: _FakePalette()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return engine;
  }

  BoxDecoration atmosphere(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find.byKey(const ValueKey<String>('playback-queue-atmosphere')),
              )
              .decoration
          as BoxDecoration;

  SonusColors themeColors(WidgetTester tester) => SonusTheme.of(
    tester.element(find.byKey(const ValueKey<String>('playback-queue-page'))),
  ).colors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final light = la > lb ? la : lb;
    final dark = la > lb ? lb : la;
    return (light + 0.05) / (dark + 0.05);
  }

  testWidgets('the current artwork tints the background behind the list, '
      'and the current row stays highlighted', (tester) async {
    await pump(tester);

    final decoration = atmosphere(tester);
    final colors = themeColors(tester);
    expect(decoration.gradient, isA<LinearGradient>());
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors.first, isNot(colors.background));
    expect(gradient.colors.last, colors.background);
    expect(
      find.byKey(const ValueKey<String>('queue-current-song-1')),
      findsOneWidget,
    );
    final row = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('queue-track-open-song-1')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(row.color, colors.selection);
  });

  for (final (label, spec) in [
    (
      'Decoration Off',
      const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
    ),
    ('High contrast', const SonusAppearanceSpec(highContrast: true)),
    ('Low effects', const SonusAppearanceSpec(lowEffects: true)),
  ]) {
    testWidgets('$label keeps the Queue flat', (tester) async {
      await pump(tester, spec: spec);

      final decoration = atmosphere(tester);
      expect(decoration.gradient, isNull);
      expect(decoration.color, themeColors(tester).background);
    });
  }

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label}: readable at 320dp with 2x text', (tester) async {
      await pump(
        tester,
        spec: SonusAppearanceSpec(themeId: id),
        size: const Size(320, 640),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final colors = themeColors(tester);
      final gradient = atmosphere(tester).gradient as LinearGradient?;
      final top = gradient?.colors.first ?? colors.background;
      expect(contrast(colors.textPrimary, top), greaterThanOrEqualTo(4.5));
      expect(contrast(colors.textSecondary, top), greaterThanOrEqualTo(4.5));
    });
  }
}
