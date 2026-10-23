import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/sonus_typography.dart';

void main() {
  test('builds every theme, typography and decoration combination', () {
    for (final themeId in SonusThemeId.values) {
      for (final typography in SonusTypographyPreset.values) {
        for (final decoration in SonusDecorationIntensity.values) {
          final theme = SonusThemeFactory.build(
            SonusAppearanceSpec(
              themeId: themeId,
              typography: typography,
              decoration: decoration,
            ),
          );

          expect(theme.extension<SonusColors>(), isNotNull);
          expect(theme.extension<SonusTextStyles>(), isNotNull);
          expect(theme.extension<SonusMetrics>(), isNotNull);
          expect(theme.extension<SonusDecorationTokens>(), isNotNull);
          expect(theme.extension<SonusMotion>(), isNotNull);
        }
      }
    }
  });

  test('maps the palette onto Material roles', () {
    for (final definition in SonusThemeCatalog.all) {
      final theme = SonusThemeFactory.build(
        SonusAppearanceSpec(themeId: definition.id),
      );
      final palette = definition.palette;

      expect(theme.brightness, palette.brightness);
      expect(theme.colorScheme.primary, palette.primary);
      expect(theme.colorScheme.secondary, palette.secondary);
      expect(theme.scaffoldBackgroundColor, palette.background);
      expect(theme.colorScheme.onSurface, palette.text);
      expect(
        theme.extension<SonusMetrics>()!.artworkRadius,
        definition.artworkRadius,
      );
    }
  });

  test('every theme and preset can be animated into every other', () {
    // AnimatedTheme interpolates on each change; mismatched text styles
    // would throw mid-transition.
    final specs = [
      for (final themeId in SonusThemeId.values)
        SonusAppearanceSpec(themeId: themeId),
      for (final typography in SonusTypographyPreset.values)
        SonusAppearanceSpec(typography: typography),
      const SonusAppearanceSpec(highContrast: true, lowEffects: true),
    ];

    for (final from in specs) {
      for (final to in specs) {
        final lerped = ThemeData.lerp(
          SonusThemeFactory.build(from),
          SonusThemeFactory.build(to),
          0.5,
        );

        expect(lerped.extension<SonusColors>(), isNotNull);
      }
    }
  });

  test('returns the cached theme for an equal spec', () {
    const spec = SonusAppearanceSpec(themeId: SonusThemeId.kickflip);

    expect(
      identical(
        SonusThemeFactory.build(spec),
        SonusThemeFactory.build(
          const SonusAppearanceSpec(themeId: SonusThemeId.kickflip),
        ),
      ),
      isTrue,
    );
  });

  group('decoration', () {
    SonusDecorationTokens decorationOf(SonusAppearanceSpec spec) =>
        SonusThemeFactory.build(spec).extension<SonusDecorationTokens>()!;

    test('defaults to Standard with texture for Concrete & Spray', () {
      final decoration = decorationOf(const SonusAppearanceSpec());

      expect(decoration.intensity, SonusDecorationIntensity.standard);
      expect(decoration.showTexture, isTrue);
      expect(decoration.showMarks, isTrue);
    });

    test('Off shows no marks, texture, glow or gradients', () {
      final decoration = decorationOf(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      );

      expect(decoration.showMarks, isFalse);
      expect(decoration.showTexture, isFalse);
      expect(decoration.allowGlow, isFalse);
      expect(decoration.allowGradients, isFalse);
      expect(decoration.markOpacity, 0);
    });

    for (final (name, spec) in [
      (
        'low effects',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          lowEffects: true,
        ),
      ),
      (
        'high contrast',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          highContrast: true,
        ),
      ),
    ]) {
      test('$name caps decoration at Subtle and drops effects', () {
        final decoration = decorationOf(spec);

        expect(decoration.intensity, SonusDecorationIntensity.subtle);
        expect(decoration.showTexture, isFalse);
        expect(decoration.allowGlow, isFalse);
        expect(decoration.allowGradients, isFalse);
      });
    }

    test('low effects keeps Off as Off', () {
      final decoration = decorationOf(
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.off,
          lowEffects: true,
        ),
      );

      expect(decoration.intensity, SonusDecorationIntensity.off);
    });
  });

  group('motion', () {
    test('reduced motion zeroes durations and page transitions', () {
      final theme = SonusThemeFactory.build(
        const SonusAppearanceSpec(reduceMotion: true),
      );
      final motion = theme.extension<SonusMotion>()!;

      expect(motion.reduced, isTrue);
      expect(motion.short, Duration.zero);
      expect(motion.medium, Duration.zero);
      expect(motion.long, Duration.zero);
      const page = SizedBox();
      final route = MaterialPageRoute<void>(builder: (_) => page);
      addTearDown(route.dispose);

      for (final platform in TargetPlatform.values) {
        final builder = theme.pageTransitionsTheme.builders[platform]!;

        // The page is shown as-is: no slide, fade or zoom.
        expect(
          identical(
            builder.buildTransitions(
              route,
              _FakeContext(),
              kAlwaysDismissedAnimation,
              kAlwaysDismissedAnimation,
              page,
            ),
            page,
          ),
          isTrue,
          reason: platform.name,
        );
      }
    });

    test('normal motion keeps Material page transitions', () {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());

      expect(theme.extension<SonusMotion>()!.medium, isNot(Duration.zero));
      expect(theme.pageTransitionsTheme, const PageTransitionsTheme());
    });
  });

  group('typography', () {
    TextTheme textOf(SonusTypographyPreset preset) => SonusThemeFactory.build(
      SonusAppearanceSpec(typography: preset),
    ).textTheme;

    test('presets change display headings', () {
      final street = textOf(SonusTypographyPreset.streetBold);
      final editorial = textOf(SonusTypographyPreset.editorial);
      final classic = textOf(SonusTypographyPreset.classicUi);

      expect(street.headlineMedium!.fontWeight, FontWeight.w900);
      expect(editorial.headlineMedium!.fontFamily, 'serif');
      expect(classic.headlineMedium!.fontWeight, FontWeight.w700);
      expect(
        street.headlineMedium!.fontSize,
        greaterThan(classic.headlineMedium!.fontSize!),
      );
    });

    test('presets keep everyday text identical and readable', () {
      final styles = [
        for (final preset in SonusTypographyPreset.values) textOf(preset),
      ];

      for (final text in styles.skip(1)) {
        expect(text.bodyLarge, styles.first.bodyLarge);
        expect(text.bodyMedium, styles.first.bodyMedium);
        expect(text.titleMedium, styles.first.titleMedium);
        expect(text.titleSmall, styles.first.titleSmall);
        expect(text.labelLarge, styles.first.labelLarge);
      }

      expect(styles.first.bodyMedium!.fontFamily, isNot('serif'));
    });

    test('featured figures use tabular digits', () {
      final styles = SonusThemeFactory.build(
        const SonusAppearanceSpec(),
      ).extension<SonusTextStyles>()!;

      for (final style in [
        styles.featuredStat,
        styles.chartRank,
        styles.numeric,
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });
  });
}

// The instant transition builder never reads its context.
class _FakeContext extends Fake implements BuildContext {}
