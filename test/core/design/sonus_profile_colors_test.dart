// UI redesign P1/P2: the Artist and Album Profiles take the artwork's own
// colour, in the user's theme brightness, with accessibility first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_profile_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

(SonusColors, SonusDecorationTokens, Brightness) tokensFor(
  SonusAppearanceSpec spec,
) {
  final theme = SonusThemeFactory.build(spec);
  return (
    theme.extension<SonusColors>()!,
    theme.extension<SonusDecorationTokens>()!,
    theme.brightness,
  );
}

double hueOf(Color colour) => HSLColor.fromColor(colour).hue;

/// The shortest distance between two hues, in degrees.
double hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  // As Material extracts them: deep containers for a dark theme, pale ones
  // for a light theme.
  const dark = <String, SonusArtworkColors>{
    'midnight blue': SonusArtworkColors(
      accent: Color(0xFFAFC6FF),
      container: Color(0xFF14306B),
    ),
    'vibrant pink': SonusArtworkColors(
      accent: Color(0xFFFFB0CF),
      container: Color(0xFF8A1F58),
    ),
    'forest green': SonusArtworkColors(
      accent: Color(0xFF8FD99A),
      container: Color(0xFF1C5228),
    ),
    'bright yellow': SonusArtworkColors(
      accent: Color(0xFFFFE066),
      container: Color(0xFFE8C840),
    ),
    'near white': SonusArtworkColors(
      accent: Color(0xFFF0F0F0),
      container: Color(0xFFEDEDED),
    ),
  };
  const light = <String, SonusArtworkColors>{
    'midnight blue': SonusArtworkColors(
      accent: Color(0xFF2B4FA0),
      container: Color(0xFFD9E2FF),
    ),
    'vibrant pink': SonusArtworkColors(
      accent: Color(0xFFA3216A),
      container: Color(0xFFFFD8E6),
    ),
    'forest green': SonusArtworkColors(
      accent: Color(0xFF2C6B39),
      container: Color(0xFFB9F0BF),
    ),
    'deep black': SonusArtworkColors(
      accent: Color(0xFF101010),
      container: Color(0xFF151515),
    ),
  };

  SonusArtworkColors artworkFor(String name, Brightness brightness) =>
      (brightness == Brightness.dark ? dark : light)[name]!;

  group('the artwork\'s own colour', () {
    for (final themeId in SonusThemeId.values) {
      final (colors, decoration, brightness) = tokensFor(
        SonusAppearanceSpec(themeId: themeId),
      );
      for (final name in ['midnight blue', 'vibrant pink', 'forest green']) {
        test('${themeId.label}: $name artwork gives a $name page', () {
          final artwork = artworkFor(name, brightness);
          final profile = SonusProfileColors.resolve(
            colors: colors,
            decoration: decoration,
            artwork: artwork,
          );

          expect(profile.isTinted, isTrue);
          final saturation = HSLColor.fromColor(profile.background).saturation;
          // A tinted page carries the artwork's hue, clearly.
          expect(saturation, greaterThan(0.08), reason: 'visibly coloured');
          expect(
            hueDistance(hueOf(profile.background), hueOf(artwork.container)),
            lessThan(40),
            reason: 'the page is the artwork\'s colour, not the theme\'s',
          );
        });
      }
    }

    test('stronger than the quieter theme atmosphere', () {
      final (colors, decoration, brightness) = tokensFor(
        const SonusAppearanceSpec(),
      );
      final artwork = artworkFor('midnight blue', brightness);
      final profile = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artwork,
      );
      final quiet = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artwork,
      );

      expect(profile.strength, greaterThan(quiet.strength));
    });

    test('the tint fades toward the theme lower down the page', () {
      final (colors, decoration, brightness) = tokensFor(
        const SonusAppearanceSpec(),
      );
      final profile = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artworkFor('vibrant pink', brightness),
      );

      double distance(Color a, Color b) =>
          (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      expect(
        distance(profile.backgroundDeep, colors.background),
        lessThan(distance(profile.background, colors.background)),
      );
    });
  });

  group('contrast guarantees', () {
    for (final themeId in SonusThemeId.values) {
      for (final intensity in SonusDecorationIntensity.values) {
        final spec = SonusAppearanceSpec(
          themeId: themeId,
          decoration: intensity,
        );
        final (colors, decoration, brightness) = tokensFor(spec);
        final artworks = brightness == Brightness.dark ? dark : light;
        for (final MapEntry(key: name, value: artwork) in artworks.entries) {
          test('${themeId.label}, ${intensity.label}, $name', () {
            final profile = SonusProfileColors.resolve(
              colors: colors,
              decoration: decoration,
              artwork: artwork,
            );
            final grounds = {
              'background': (colors.background, profile.background),
              'lower page': (colors.background, profile.backgroundDeep),
              'surface': (colors.surface, profile.surface),
              // V1: the soft glass (SonusSoftGlass) over the page, with
              // its highlight, and the page under its brightest light.
              'glass': (
                colors.background,
                Color.alphaBlend(
                  Colors.white.withValues(
                    alpha: SonusProfileColors.glassHighlight,
                  ),
                  Color.alphaBlend(
                    profile.surface.withValues(
                      alpha: SonusProfileColors.glassAlpha,
                    ),
                    profile.backgroundDeep,
                  ),
                ),
              ),
              'ambient light': (
                colors.background,
                Color.alphaBlend(
                  profile.light.withValues(
                    alpha: SonusProfileColors.ambientAlpha,
                  ),
                  profile.background,
                ),
              ),
            };
            for (final MapEntry(key: ground, value: (themeGround, tinted))
                in grounds.entries) {
              for (final text in [colors.textPrimary, colors.textSecondary]) {
                final required = SonusContrast.ratio(
                  text,
                  themeGround,
                ).clamp(1.0, 4.5);
                expect(
                  SonusContrast.ratio(text, tinted),
                  greaterThanOrEqualTo(required - 0.01),
                  reason: 'text on $ground',
                );
              }
              if (profile.accent != colors.accentPrimary) {
                expect(
                  SonusContrast.ratio(profile.accent, tinted),
                  greaterThanOrEqualTo(3),
                  reason: 'accent on $ground',
                );
              }
            }
            expect(
              SonusContrast.ratio(profile.onAccent, profile.accent),
              greaterThanOrEqualTo(
                profile.accent == colors.accentPrimary
                    ? SonusContrast.ratio(
                            colors.onAccentPrimary,
                            colors.accentPrimary,
                          ) -
                          0.01
                    : 4.5,
              ),
            );
          });
        }
      }
    }
  });

  group('accessibility settings come first', () {
    for (final (label, spec) in [
      (
        'Decoration Off',
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
      (
        'High contrast',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          highContrast: true,
        ),
      ),
      (
        'Low effects',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          lowEffects: true,
        ),
      ),
    ]) {
      test('$label: the theme\'s flat colours, no glow', () {
        final (colors, decoration, brightness) = tokensFor(spec);
        final profile = SonusProfileColors.resolve(
          colors: colors,
          decoration: decoration,
          artwork: artworkFor('vibrant pink', brightness),
        );

        expect(profile.isTinted, isFalse);
        expect(profile.background, colors.background);
        expect(profile.backgroundDeep, colors.background);
        expect(profile.surface, colors.surface);
        expect(profile.accent, colors.accentPrimary);
        expect(profile.hasGlow, isFalse);
        expect(profile.edge, colors.border);
      });
    }

    test('Subtle tints the page but keeps the theme accent', () {
      final (colors, decoration, brightness) = tokensFor(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.subtle),
      );
      final profile = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artworkFor('midnight blue', brightness),
      );

      expect(profile.isTinted, isTrue);
      expect(profile.accent, colors.accentPrimary);
    });
  });

  test('no artwork: the theme\'s colours', () {
    final (colors, decoration, _) = tokensFor(const SonusAppearanceSpec());
    final profile = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
    );

    expect(profile.isTinted, isFalse);
    expect(profile.background, colors.background);
    expect(profile.surface, colors.surface);
    expect(profile.accent, colors.accentPrimary);
    expect(profile.atmosphere.background, colors.background);
  });

  test('blends without a low-contrast midpoint for text on the accent', () {
    final (colors, decoration, brightness) = tokensFor(
      const SonusAppearanceSpec(),
    );
    final a = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
    );
    final b = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
      artwork: artworkFor('vibrant pink', brightness),
    );

    expect(SonusProfileColors.lerp(a, b, 0.4).onAccent, a.onAccent);
    expect(SonusProfileColors.lerp(a, b, 0.6).onAccent, b.onAccent);
    expect(SonusProfileColors.lerp(a, b, 1), b);
  });
}
