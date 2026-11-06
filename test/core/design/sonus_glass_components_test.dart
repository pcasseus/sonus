import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_cinematic_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_artwork_backdrop.dart';
import 'package:sonus_next/core/design/widgets/sonus_glass_panel.dart';
import 'package:sonus_next/core/design/widgets/sonus_perspective_panel.dart';

const _limited = [
  ('High contrast', SonusAppearanceSpec(highContrast: true)),
  ('Low effects', SonusAppearanceSpec(lowEffects: true)),
  (
    'Decoration Off',
    SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
  ),
];

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
}

BoxDecoration surfaceOf(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find.byKey(const ValueKey<String>('sonus-glass-panel-surface')),
            )
            .decoration
        as BoxDecoration;

void main() {
  const base = Color(0xFF19151F);
  const edge = Color(0x66B78CFF);
  const glow = Color(0x73B78CFF);

  Widget panel({bool backdropBlur = false}) => SonusGlassPanel(
    base: base,
    edge: edge,
    glow: glow,
    backdropBlur: backdropBlur,
    child: const Text('2 Albums'),
  );

  group('SonusGlow', () {
    test('glows only where glow is allowed', () {
      final allowed = SonusThemeFactory.build(
        const SonusAppearanceSpec(),
      ).extension<SonusDecorationTokens>()!;
      final limited = SonusThemeFactory.build(
        const SonusAppearanceSpec(lowEffects: true),
      ).extension<SonusDecorationTokens>()!;

      expect(SonusGlow.shadows(glow, allowed), hasLength(1));
      expect(SonusGlow.shadows(glow, limited), isEmpty);
      expect(SonusGlow.shadows(const Color(0x00000000), allowed), isEmpty);
    });
  });

  group('SonusGlassPanel', () {
    testWidgets('is translucent glass with a rim and a glow by default', (
      tester,
    ) async {
      await pump(tester, panel());

      final surface = surfaceOf(tester);
      expect(surface.gradient, isNotNull);
      expect(surface.color, isNull);
      expect(surface.border, isNotNull);
      expect(surface.boxShadow, isNotEmpty);
      expect(find.text('2 Albums'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'no live blur');
    });

    for (final (name, spec) in _limited) {
      testWidgets('$name: opaque, solid border, no glow, no blur', (
        tester,
      ) async {
        await pump(tester, panel(backdropBlur: true), spec: spec);

        final surface = surfaceOf(tester);
        expect(surface.gradient, isNull);
        expect(surface.color, base);
        expect(surface.color!.a, 1);
        expect(surface.boxShadow ?? const [], isEmpty);
        expect(find.byType(BackdropFilter), findsNothing);
      });
    }

    testWidgets('a live blur only when asked for and allowed', (tester) async {
      await pump(tester, panel(backdropBlur: true));
      expect(
        find.byKey(const ValueKey<String>('sonus-glass-panel-blur')),
        findsOneWidget,
      );

      await pump(
        tester,
        panel(backdropBlur: true),
        spec: const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.subtle,
        ),
      );
      // MaterialApp animates from the previous theme; let it arrive.
      await tester.pumpAndSettle();
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'Subtle allows no glow, so no blur either',
      );
    });
  });

  group('SonusPerspectivePanel', () {
    Widget tilted(VoidCallback onTap) => Center(
      child: SonusPerspectivePanel(
        angle: 0.35,
        alignment: Alignment.centerLeft,
        child: ElevatedButton(onPressed: onTap, child: const Text('Albums')),
      ),
    );

    testWidgets('tilts its child, which still takes taps', (tester) async {
      var taps = 0;
      await pump(tester, tilted(() => taps++));

      expect(
        find.byKey(const ValueKey<String>('sonus-perspective-panel-transform')),
        findsOneWidget,
      );
      await tester.tap(find.text('Albums'));
      expect(taps, 1);
    });

    for (final (name, spec) in _limited) {
      testWidgets('$name: stays flat', (tester) async {
        await pump(tester, tilted(() {}), spec: spec);

        expect(
          find.byKey(
            const ValueKey<String>('sonus-perspective-panel-transform'),
          ),
          findsNothing,
        );
      });
    }
  });

  group('SonusArtworkBackdrop', () {
    Widget backdrop(String? path) => SonusArtworkBackdrop(
      artworkPath: path,
      top: SonusCinematicColors.baseBackground,
      bottom: SonusCinematicColors.baseBackgroundDeep,
    );

    Finder image() =>
        find.byKey(const ValueKey<String>('sonus-artwork-backdrop-image'));

    testWidgets('a tiny blurred copy of the artwork under its colours', (
      tester,
    ) async {
      await pump(tester, backdrop('/art/cover.jpg'));

      expect(image(), findsOneWidget);
      final picture = tester.widget<Image>(
        find.descendant(of: image(), matching: find.byType(Image)),
      );
      expect(picture.image, isA<ResizeImage>());
      expect(
        (picture.image as ResizeImage).width,
        SonusArtworkBackdrop.decodeWidth,
      );
    });

    testWidgets('is never read by screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, backdrop('/art/cover.jpg'));

      expect(
        find.ancestor(of: image(), matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('no artwork: colours only', (tester) async {
      await pump(tester, backdrop(null));
      expect(image(), findsNothing);
    });

    for (final (name, spec) in _limited) {
      testWidgets('$name: flat colour, no image', (tester) async {
        await pump(tester, backdrop('/art/cover.jpg'), spec: spec);

        expect(image(), findsNothing);
        final colours =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(
                        const ValueKey<String>(
                          'sonus-artwork-backdrop-colours',
                        ),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(colours.gradient, isNull);
        expect(colours.color, SonusCinematicColors.baseBackground);
      });
    }
  });

  // The pieces together, as the Film Reel will combine them.
  for (final id in SonusThemeId.values) {
    testWidgets('${id.label}: glass on a backdrop fits 320dp at 2x text', (
      tester,
    ) async {
      await pump(
        tester,
        Stack(
          fit: StackFit.expand,
          children: [
            SonusArtworkBackdrop(
              artworkPath: '/art/cover.jpg',
              top: SonusCinematicColors.baseBackground,
              bottom: SonusCinematicColors.baseBackgroundDeep,
            ),
            Center(
              child: SonusPerspectivePanel(
                angle: 0.3,
                child: SizedBox(width: 140, child: panel()),
              ),
            ),
          ],
        ),
        spec: SonusAppearanceSpec(themeId: id),
        size: const Size(320, 640),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
