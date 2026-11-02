import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_colors.dart';

PulsePalette paletteFor(
  SonusThemeId id, {
  SonusDecorationIntensity decoration = SonusDecorationIntensity.standard,
  bool highContrast = false,
  bool lowEffects = false,
  SonusArtworkColors? artwork,
}) {
  final definition = SonusThemeCatalog.of(id);
  final spec = SonusAppearanceSpec(
    themeId: id,
    decoration: decoration,
    highContrast: highContrast,
    lowEffects: lowEffects,
  );
  return PulsePalette.resolve(
    colors: SonusThemeFactory.colorsFor(definition, highContrast: highContrast),
    decoration: SonusThemeFactory.decorationFor(definition, spec),
    highContrast: highContrast,
    artwork: artwork,
  );
}

double hueGap(Color a, Color b) {
  final d = (Oklch.fromColor(a).h - Oklch.fromColor(b).h).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  test('OKLCH round-trips sRGB', () {
    for (final colour in [
      const Color(0xFF398BFF),
      const Color(0xFFFF4F91),
      const Color(0xFF111111),
      Colors.white,
    ]) {
      final back = Oklch.fromColor(colour).toColor();
      expect((back.r - colour.r).abs() < 0.003, isTrue);
      expect((back.g - colour.g).abs() < 0.003, isTrue);
      expect((back.b - colour.b).abs() < 0.003, isTrue);
    }
  });

  for (final id in SonusThemeId.values) {
    group(id.label, () {
      test('every step of every family keeps 3:1 against the surface', () {
        final palette = paletteFor(id);
        for (final ramp in [
          palette.minutes,
          palette.streams,
          palette.allPlays,
        ]) {
          expect(ramp.steps, hasLength(PulsePalette.gradientSteps));
          for (final step in ramp.steps) {
            expect(
              SonusContrast.ratio(step, palette.surface),
              greaterThanOrEqualTo(PulsePalette.minimumContrast - 0.01),
            );
          }
        }
      });

      test('the three families are distinguishable', () {
        final p = paletteFor(id);
        final families = [p.minutes, p.streams, p.allPlays];
        for (var i = 0; i < 3; i++) {
          for (var j = i + 1; j < 3; j++) {
            final a = families[i];
            final b = families[j];
            final distinct =
                a.pattern != b.pattern ||
                hueGap(a.base, b.base) >= 20 ||
                (Oklch.fromColor(a.mid).l - Oklch.fromColor(b.mid).l).abs() >=
                    0.04;
            expect(distinct, isTrue, reason: 'families $i and $j');
          }
        }
      });

      test('ramps brighten from base to tip and colour tips by value', () {
        final ramp = paletteFor(id).minutes;
        expect(
          Oklch.fromColor(ramp.tip).l,
          greaterThan(Oklch.fromColor(ramp.base).l),
        );
        expect(ramp.at(0), ramp.base);
        expect(ramp.at(1), ramp.tip);
      });
    });
  }

  test('colourful themes stay vivid: chroma floor lifts muted palettes', () {
    for (final id in [
      SonusThemeId.daylight,
      SonusThemeId.evergreen,
      SonusThemeId.haze2017,
      SonusThemeId.concreteSpray,
    ]) {
      final mid = Oklch.fromColor(paletteFor(id).minutes.mid);
      expect(mid.c, greaterThan(0.08), reason: id.label);
    }
  });

  test('Monochrome is greyscale, distinguished by tone and pattern', () {
    final p = paletteFor(SonusThemeId.monochrome);
    expect(p.isMonochrome, isTrue);
    for (final ramp in [p.minutes, p.streams, p.allPlays]) {
      for (final step in ramp.steps) {
        expect(Oklch.fromColor(step).c, lessThan(0.005));
      }
    }
    expect(
      {p.minutes.pattern, p.streams.pattern, p.allPlays.pattern},
      {PulseBarPattern.solid, PulseBarPattern.stripe, PulseBarPattern.dotted},
    );
    expect(paletteFor(SonusThemeId.neonMixtape).isMonochrome, isFalse);
  });

  test('Decoration Off and Low effects: five solid steps, no halo or glow', () {
    for (final palette in [
      paletteFor(
        SonusThemeId.neonMixtape,
        decoration: SonusDecorationIntensity.off,
      ),
      paletteFor(SonusThemeId.neonMixtape, lowEffects: true),
    ]) {
      expect(palette.minutes.fill, PulseFill.stepped);
      expect(palette.minutes.steps, hasLength(PulsePalette.solidSteps));
      expect(palette.haloStrength, 0);
      expect(palette.allowGlow, isFalse);
    }
  });

  test('High contrast: one solid colour per metric; artwork only as an '
      'outline', () {
    const artwork = SonusArtworkColors(
      accent: Color(0xFFE53935),
      container: Color(0xFF3B0D0C),
    );
    final p = paletteFor(
      SonusThemeId.afterHours,
      highContrast: true,
      artwork: artwork,
    );
    expect(p.minutes.fill, PulseFill.solid);
    expect(p.minutes.steps, hasLength(1));
    expect(p.minutes.tip, isNot(p.streams.tip));
    expect(p.haloStrength, 0);
    expect(p.itemOutlineOnly, isTrue);
    expect(p.itemColorFor(PulseMeasure.minutes), p.text);
  });

  test('halo follows the decoration scale', () {
    expect(
      paletteFor(
        SonusThemeId.kickflip,
        decoration: SonusDecorationIntensity.subtle,
      ).haloStrength,
      0.10,
    );
    expect(paletteFor(SonusThemeId.kickflip).haloStrength, 0.20);
    expect(
      paletteFor(
        SonusThemeId.kickflip,
        decoration: SonusDecorationIntensity.expressive,
      ).haloStrength,
      0.32,
    );
  });

  test('an artwork accent is temporary: resolving without it is the theme', () {
    const artwork = SonusArtworkColors(
      accent: Color(0xFFFFB300),
      container: Color(0xFF3D2A00),
    );
    final withArt = paletteFor(SonusThemeId.concreteSpray, artwork: artwork);
    final reset = paletteFor(SonusThemeId.concreteSpray);

    expect(withArt.itemAccent, isNotNull);
    expect(withArt.haloFor(PulseMeasure.minutes), withArt.itemAccent);
    expect(
      SonusContrast.ratio(withArt.itemAccent!, withArt.surface),
      greaterThanOrEqualTo(3 - 0.01),
    );
    expect(reset.itemAccent, isNull);
    expect(reset.haloFor(PulseMeasure.minutes), reset.minutes.mid);
    expect(reset.minutes.steps, withArt.minutes.steps);
  });
}
