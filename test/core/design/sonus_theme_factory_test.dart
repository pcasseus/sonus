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

  group('navigation tabs', () {
    for (final id in SonusThemeId.values) {
      test('${id.label} gives focused tabs a stronger wash', () {
        final theme = SonusThemeFactory.build(SonusAppearanceSpec(themeId: id));
        final colors = theme.extension<SonusColors>()!;
        final overlay = theme.tabBarTheme.overlayColor!;

        expect(
          overlay.resolve({WidgetState.focused}),
          colors.focus.withValues(alpha: 0.24),
        );
        expect(overlay.resolve({WidgetState.pressed}), colors.selection);
        expect(overlay.resolve({}), colors.selection);
      });
    }

    test('tab ripples follow the control radius', () {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final metrics = theme.extension<SonusMetrics>()!;

      expect(
        theme.tabBarTheme.splashBorderRadius,
        BorderRadius.circular(metrics.controlRadius),
      );
    });
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

    test('bold text raises every weight and keeps the hierarchy', () {
      for (final preset in SonusTypographyPreset.values) {
        // Theme.of adds the Material geometry; compare what screens see.
        TextTheme resolved(bool bold) => ThemeData.localize(
          SonusThemeFactory.build(
            SonusAppearanceSpec(typography: preset, boldText: bold),
          ),
          Typography.material2021().englishLike,
        ).textTheme;

        final plain = resolved(false);
        final bold = resolved(true);

        List<TextStyle> all(TextTheme t) => [
          t.displayLarge!,
          t.displayMedium!,
          t.displaySmall!,
          t.headlineLarge!,
          t.headlineMedium!,
          t.headlineSmall!,
          t.titleLarge!,
          t.titleMedium!,
          t.titleSmall!,
          t.bodyLarge!,
          t.bodyMedium!,
          t.bodySmall!,
          t.labelLarge!,
          t.labelMedium!,
          t.labelSmall!,
        ];

        final before = all(plain);
        final after = all(bold);

        for (var i = 0; i < before.length; i++) {
          final from = before[i].fontWeight!;
          final to = after[i].fontWeight!;
          expect(to, SonusTypography.bolder(from), reason: '${preset.name} $i');
          expect(to.value, greaterThanOrEqualTo(from.value));
          expect(after[i].fontSize, before[i].fontSize);
          expect(after[i].color, before[i].color);
          expect(after[i].fontFamily, before[i].fontFamily);

          // A style that was at least as heavy as another stays so.
          for (var j = 0; j < before.length; j++) {
            if (before[i].fontWeight!.value >= before[j].fontWeight!.value) {
              expect(
                after[i].fontWeight!.value,
                greaterThanOrEqualTo(after[j].fontWeight!.value),
              );
            }
          }
        }
      }

      expect(SonusTypography.bolder(FontWeight.w400), FontWeight.w600);
      expect(SonusTypography.bolder(FontWeight.w500), FontWeight.w700);
      expect(SonusTypography.bolder(FontWeight.w600), FontWeight.w800);
      expect(SonusTypography.bolder(FontWeight.w800), FontWeight.w900);
      expect(SonusTypography.bolder(FontWeight.w900), FontWeight.w900);
    });

    test('bold text also raises Sonus heading styles and tab labels', () {
      final plain = SonusThemeFactory.build(const SonusAppearanceSpec());
      final bold = SonusThemeFactory.build(
        const SonusAppearanceSpec(boldText: true),
      );

      final plainText = plain.extension<SonusTextStyles>()!;
      final boldText = bold.extension<SonusTextStyles>()!;
      expect(boldText.sectionHeading.fontWeight, FontWeight.w900);
      expect(boldText.chartRank.fontWeight, FontWeight.w900);
      expect(plainText.sectionHeading.fontWeight, FontWeight.w700);
      expect(
        bold.tabBarTheme.unselectedLabelStyle!.fontWeight,
        FontWeight.w700,
      );
      expect(
        plain.tabBarTheme.unselectedLabelStyle!.fontWeight,
        FontWeight.w500,
      );
    });

    test('bold text never changes colours or decoration', () {
      for (final themeId in SonusThemeId.values) {
        for (final decoration in SonusDecorationIntensity.values) {
          for (final highContrast in [false, true]) {
            for (final lowEffects in [false, true]) {
              SonusAppearanceSpec spec(bool bold) => SonusAppearanceSpec(
                themeId: themeId,
                decoration: decoration,
                highContrast: highContrast,
                lowEffects: lowEffects,
                boldText: bold,
              );
              final plain = SonusThemeFactory.build(spec(false));
              final bold = SonusThemeFactory.build(spec(true));
              final a = plain.extension<SonusDecorationTokens>()!;
              final b = bold.extension<SonusDecorationTokens>()!;
              final reason =
                  '${themeId.name} ${decoration.name} hc=$highContrast '
                  'le=$lowEffects';

              expect(b.intensity, a.intensity, reason: reason);
              expect(b.allowGradients, a.allowGradients, reason: reason);
              expect(b.allowGlow, a.allowGlow, reason: reason);
              expect(b.highContrast, a.highContrast, reason: reason);
              expect(b.lowEffects, a.lowEffects, reason: reason);
              expect(b.showTexture, a.showTexture, reason: reason);
              expect(b.markOpacity, a.markOpacity, reason: reason);
              expect(b.textureOpacity, a.textureOpacity, reason: reason);
              expect(b.reactivity, a.reactivity, reason: reason);
              expect(b.motif, a.motif, reason: reason);
              expect(b.progressStyle, a.progressStyle, reason: reason);
              expect(bold.colorScheme, plain.colorScheme, reason: reason);
              expect(
                bold.extension<SonusColors>()!.textSecondary,
                plain.extension<SonusColors>()!.textSecondary,
                reason: reason,
              );
            }
          }
        }
      }

      // Bold text alone keeps the full atmosphere.
      final boldOnly = SonusThemeFactory.build(
        const SonusAppearanceSpec(boldText: true),
      ).extension<SonusDecorationTokens>()!;
      expect(boldOnly.allowGradients, isTrue);
      expect(boldOnly.allowGlow, isTrue);
      expect(boldOnly.highContrast, isFalse);
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

  // Theme architecture T0: the effects layer is readable from the tokens.
  test(
    'decoration tokens carry the accessibility settings that shaped them',
    () {
      SonusDecorationTokens tokens(SonusAppearanceSpec spec) =>
          SonusThemeFactory.build(spec).extension<SonusDecorationTokens>()!;

      final plain = tokens(const SonusAppearanceSpec());
      expect(plain.highContrast, isFalse);
      expect(plain.lowEffects, isFalse);

      final contrast = tokens(const SonusAppearanceSpec(highContrast: true));
      expect(contrast.highContrast, isTrue);
      expect(contrast.allowGradients, isFalse);

      final effects = tokens(const SonusAppearanceSpec(lowEffects: true));
      expect(effects.lowEffects, isTrue);
      expect(effects.allowGlow, isFalse);
    },
  );
}

// The instant transition builder never reads its context.
class _FakeContext extends Fake implements BuildContext {}
