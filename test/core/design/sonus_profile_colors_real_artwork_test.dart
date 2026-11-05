// Device audit (2026-11-04): the colours Sonus's own extraction
// (SonusArtworkPalette.extractFromImage, dark theme) returned for real
// library artwork. Bright artwork gives light "containers"; the profile
// colours used to tint toward them, broke text contrast, and the contrast
// guard removed the tint entirely, leaving plain charcoal pages. These
// values pin the fix: the page carries each artwork's hue, readably.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_profile_colors.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

(SonusColors, SonusDecorationTokens) tokensFor(SonusAppearanceSpec spec) {
  final theme = SonusThemeFactory.build(spec);
  return (
    theme.extension<SonusColors>()!,
    theme.extension<SonusDecorationTokens>()!,
  );
}

double hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

HSLColor hsl(Color colour) => HSLColor.fromColor(colour);

/// Real extracted values (accent, container), as SonusArtworkPalette
/// returned them for the user's library artwork.
const real = <String, SonusArtworkColors>{
  // Cool: pale blue banner, the locket covers.
  'artist banner, cool blue': SonusArtworkColors(
    accent: Color(0xFF9BCDEA),
    container: Color(0xFF6597B2),
  ),
  'album cover, cool blue (standard edition)': SonusArtworkColors(
    accent: Color(0xFF94CFE9),
    container: Color(0xFF629CB5),
  ),
  'album cover, blue-grey (deluxe edition)': SonusArtworkColors(
    accent: Color(0xFFB6C8DC),
    container: Color(0xFF374858),
  ),
  // Warm: an orange-lit banner.
  'artist banner, warm orange': SonusArtworkColors(
    accent: Color(0xFFFFB68F),
    container: Color(0xFFDA7639),
  ),
  // Yellow, with a white accent.
  'album cover, yellow (standard edition)': SonusArtworkColors(
    accent: Color(0xFFFFFFFF),
    container: Color(0xFFECE913),
  ),
  // Pink and red.
  'album cover, red-pink (deluxe edition)': SonusArtworkColors(
    accent: Color(0xFFFFB4AA),
    container: Color(0xFFBD2821),
  ),
  'artist portrait, pink': SonusArtworkColors(
    accent: Color(0xFFFFB3B4),
    container: Color(0xFFFD5463),
  ),
};

/// Shapes the real library did not provide, extracted the same way.
const synthetic = <String, SonusArtworkColors>{
  'bright green': SonusArtworkColors(
    accent: Color(0xFFA6F2AE),
    container: Color(0xFF6FCF7A),
  ),
  'deep green': SonusArtworkColors(
    accent: Color(0xFF8FD99A),
    container: Color(0xFF1C5228),
  ),
};

/// Near-white artwork with the faintest colour cast.
const nearWhite = SonusArtworkColors(
  accent: Color(0xFFF4F6F8),
  container: Color(0xFFE8ECF0),
);

void main() {
  final all = {...real, ...synthetic};

  group('real artwork keeps its hue on the page', () {
    final (colors, decoration) = tokensFor(const SonusAppearanceSpec());
    final target = SonusProfileColors.strengthFor(decoration.intensity);

    for (final MapEntry(key: name, value: artwork) in all.entries) {
      test(name, () {
        final profile = SonusProfileColors.resolve(
          colors: colors,
          decoration: decoration,
          artwork: artwork,
        );
        final hue = hsl(artwork.container).hue;

        // The regression: these pages used to come out untinted (strength
        // 0). The contrast guard may still trim very luminous hues a little
        // (bright green keeps about three quarters): correct, not maximal.
        expect(profile.isTinted, isTrue);
        expect(profile.strength, greaterThanOrEqualTo(target * 0.5));
        // Gradient, glass and light all carry the artwork's hue.
        for (final (part, colour) in [
          ('page top', profile.background),
          ('page bottom', profile.backgroundDeep),
          ('glass', profile.surface),
          ('light', profile.light),
        ]) {
          expect(
            hueDistance(hsl(colour).hue, hue),
            lessThan(25),
            reason: '$part hue',
          );
          expect(hsl(colour).saturation, greaterThan(0.12), reason: part);
        }
        // Readable everywhere, accent distinct and from the artwork.
        for (final ground in [
          profile.background,
          profile.backgroundDeep,
          profile.surface,
        ]) {
          for (final text in [colors.textPrimary, colors.textSecondary]) {
            expect(
              SonusContrast.ratio(text, ground),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(
            SonusContrast.ratio(profile.accent, ground),
            greaterThanOrEqualTo(3),
          );
        }
        expect(profile.accent, isNot(colors.accentPrimary));
        expect(
          SonusContrast.ratio(profile.onAccent, profile.accent),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('a white accent on coloured artwork takes the artwork\'s hue', () {
      final artwork = real['album cover, yellow (standard edition)']!;
      final profile = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: artwork,
      );

      expect(hsl(profile.accent).saturation, greaterThan(0.4));
      expect(
        hueDistance(hsl(profile.accent).hue, hsl(artwork.container).hue),
        lessThan(10),
      );
    });

    test('distinct artwork gives distinct pages', () {
      final pages = {
        for (final MapEntry(key: name, value: artwork) in real.entries)
          name: SonusProfileColors.resolve(
            colors: colors,
            decoration: decoration,
            artwork: artwork,
          ).background,
      };
      final cool = hsl(pages['artist banner, cool blue']!).hue;
      final warm = hsl(pages['artist banner, warm orange']!).hue;
      final pink = hsl(pages['album cover, red-pink (deluxe edition)']!).hue;
      expect(hueDistance(cool, warm), greaterThan(120));
      expect(hueDistance(cool, pink), greaterThan(120));
    });
  });

  test('near-white artwork stays quiet: no invented colour', () {
    final (colors, decoration) = tokensFor(const SonusAppearanceSpec());
    final profile = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
      artwork: nearWhite,
    );

    for (final colour in [
      profile.background,
      profile.backgroundDeep,
      profile.surface,
    ]) {
      expect(hsl(colour).saturation, lessThan(0.15));
    }
    // Its accent is not replaced by a made-up hue.
    expect(hsl(profile.accent).saturation, lessThan(0.3));
    expect(
      SonusContrast.ratio(colors.textPrimary, profile.background),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('in every theme and decoration level, real artwork never falls back '
      'to an untinted page, and text stays readable', () {
    for (final themeId in SonusThemeId.values) {
      for (final intensity in [
        SonusDecorationIntensity.subtle,
        SonusDecorationIntensity.standard,
        SonusDecorationIntensity.expressive,
      ]) {
        final (colors, decoration) = tokensFor(
          SonusAppearanceSpec(themeId: themeId, decoration: intensity),
        );
        for (final MapEntry(key: name, value: artwork) in all.entries) {
          final profile = SonusProfileColors.resolve(
            colors: colors,
            decoration: decoration,
            artwork: artwork,
          );
          final where = '${themeId.label}, ${intensity.label}, $name';
          expect(profile.isTinted, isTrue, reason: where);
          for (final text in [colors.textPrimary, colors.textSecondary]) {
            final required = SonusContrast.ratio(
              text,
              colors.background,
            ).clamp(1.0, 4.5);
            expect(
              SonusContrast.ratio(text, profile.background),
              greaterThanOrEqualTo(required - 0.01),
              reason: where,
            );
          }
        }
      }
    }
  });

  test('accessibility settings still win: flat theme colours', () {
    for (final spec in const [
      SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      SonusAppearanceSpec(highContrast: true),
      SonusAppearanceSpec(lowEffects: true),
    ]) {
      final (colors, decoration) = tokensFor(spec);
      final profile = SonusProfileColors.resolve(
        colors: colors,
        decoration: decoration,
        artwork: real['artist banner, warm orange'],
      );
      expect(profile.isTinted, isFalse);
      expect(profile.background, colors.background);
      expect(profile.accent, colors.accentPrimary);
    }
  });

  test('the tone is a parameter, for Themes 2.0, not a fixed choice', () {
    final (colors, decoration) = tokensFor(const SonusAppearanceSpec());
    final artwork = real['artist banner, cool blue']!;
    final deeper = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
      artwork: artwork,
      tone: const SonusArtworkTone(
        darkTintLuminance: 0.02,
        lightTintLuminance: 0.8,
        minTintSaturation: 0,
        maxTintSaturation: 0.5,
        darkAccentLuminance: 0.45,
        lightAccentLuminance: 0.12,
        minAccentSaturation: 0.5,
        maxAccentSaturation: 0.9,
        colourlessAccentSaturation: 0.2,
      ),
    );
    final standard = SonusProfileColors.resolve(
      colors: colors,
      decoration: decoration,
      artwork: artwork,
    );

    expect(
      deeper.background.computeLuminance(),
      lessThan(standard.background.computeLuminance()),
    );
  });
}
