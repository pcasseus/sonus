import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_board_rows.dart';

// Register R11: the Top 10 frame asks the shared artwork-colours request,
// so it follows its artwork and re-asks when the brightness changes.
void main() {
  const red = Color(0xFFE53935);
  const blue = Color(0xFF1E88E5);

  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    required String? path,
    required _RecordingPalette palette,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: ChartTopTenFrame(
            artworkPath: path,
            palette: palette,
            child: const SizedBox(height: 40, width: 200),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration frame(WidgetTester tester) =>
      tester
              .widget<Container>(
                find.byKey(const ValueKey<String>('charts-top-ten-frame')),
              )
              .decoration!
          as BoxDecoration;

  testWidgets('the accent comes from the artwork and follows a new one', (
    tester,
  ) async {
    final palette = _RecordingPalette({'/a.jpg': red, '/b.jpg': blue});
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());

    await pump(tester, theme: theme, path: '/a.jpg', palette: palette);
    expect((frame(tester).gradient! as LinearGradient).colors.first, red);

    await pump(tester, theme: theme, path: '/b.jpg', palette: palette);
    expect((frame(tester).gradient! as LinearGradient).colors.first, blue);
    expect(palette.requested.map((r) => r.$1), ['/a.jpg', '/b.jpg']);
  });

  testWidgets('no artwork colours keep the theme accent', (tester) async {
    final palette = _RecordingPalette(const {});
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());

    await pump(tester, theme: theme, path: '/none.jpg', palette: palette);
    expect(
      (frame(tester).gradient! as LinearGradient).colors.first,
      theme.extension<SonusColors>()!.accentPrimary,
    );
  });

  testWidgets('a brightness change asks again (was cached by path only)', (
    tester,
  ) async {
    final palette = _RecordingPalette({'/a.jpg': red});

    await pump(
      tester,
      theme: ThemeData(brightness: Brightness.dark),
      path: '/a.jpg',
      palette: palette,
    );
    await pump(
      tester,
      theme: ThemeData(brightness: Brightness.light),
      path: '/a.jpg',
      palette: palette,
    );

    expect(palette.requested, [
      ('/a.jpg', Brightness.dark),
      ('/a.jpg', Brightness.light),
    ]);
  });

  testWidgets('Monochrome draws no artwork tint', (tester) async {
    final palette = _RecordingPalette({'/a.jpg': red});
    final theme = SonusThemeFactory.build(
      const SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
    );

    await pump(tester, theme: theme, path: '/a.jpg', palette: palette);
    final decoration = frame(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.color, theme.extension<SonusColors>()!.border);
  });
}

class _RecordingPalette extends SonusArtworkPalette {
  _RecordingPalette(this.colours);

  final Map<String, Color> colours;
  final requested = <(String?, Brightness)>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    requested.add((artworkPath, brightness));
    final accent = colours[artworkPath];
    return accent == null
        ? null
        : SonusArtworkColors(accent: accent, container: accent);
  }
}
