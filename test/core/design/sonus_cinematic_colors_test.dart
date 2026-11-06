import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_cinematic_colors.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/widgets/sonus_cinematic_atmosphere_builder.dart';

SonusDecorationTokens decorationFor(SonusAppearanceSpec spec) =>
    SonusThemeFactory.build(spec).extension<SonusDecorationTokens>()!;

void main() {
  // Container colours as extracted for a dark background, from dark and
  // muted to deliberately bright ones that strain legibility.
  const artworks = <String, SonusArtworkColors>{
    'midnight blue': SonusArtworkColors(
      accent: Color(0xFF7FA8FF),
      container: Color(0xFF14254F),
    ),
    'vibrant pink': SonusArtworkColors(
      accent: Color(0xFFFF7EB6),
      container: Color(0xFF7A1F4D),
    ),
    'bright yellow': SonusArtworkColors(
      accent: Color(0xFFFFE066),
      container: Color(0xFFE8C840),
    ),
    'near white': SonusArtworkColors(
      accent: Color(0xFFF0F0F0),
      container: Color(0xFFEDEDED),
    ),
    'dark accent': SonusArtworkColors(
      accent: Color(0xFF2A0F3D),
      container: Color(0xFF3A1A55),
    ),
  };

  group('contrast guarantees', () {
    for (final intensity in SonusDecorationIntensity.values) {
      for (final MapEntry(key: name, value: artwork) in artworks.entries) {
        test('${intensity.name}, $name', () {
          final colors = SonusCinematicColors.resolve(
            decoration: decorationFor(
              SonusAppearanceSpec(decoration: intensity),
            ),
            artwork: artwork,
          );

          for (final ground in [colors.background, colors.surface]) {
            expect(
              SonusContrast.ratio(colors.textPrimary, ground),
              greaterThanOrEqualTo(7),
            );
            expect(
              SonusContrast.ratio(colors.textSecondary, ground),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              SonusContrast.ratio(colors.accent, ground),
              greaterThanOrEqualTo(3),
            );
          }
          expect(
            SonusContrast.ratio(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  });

  test('artwork tints the base where gradients are allowed', () {
    final colors = SonusCinematicColors.resolve(
      decoration: decorationFor(const SonusAppearanceSpec()),
      artwork: artworks['vibrant pink'],
    );

    expect(colors.isTinted, isTrue);
    expect(colors.background, isNot(SonusCinematicColors.baseBackground));
    expect(colors.accent, artworks['vibrant pink']!.accent);
    expect(colors.hasGlow, isTrue);
  });

  test('a legible accent is replaced by the base accent when it is not', () {
    final colors = SonusCinematicColors.resolve(
      decoration: decorationFor(const SonusAppearanceSpec()),
      artwork: artworks['dark accent'],
    );

    expect(colors.accent, SonusCinematicColors.baseAccent);
  });

  test('Subtle tints the background but keeps the base accent', () {
    final colors = SonusCinematicColors.resolve(
      decoration: decorationFor(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.subtle),
      ),
      artwork: artworks['vibrant pink'],
    );

    expect(colors.isTinted, isTrue);
    expect(colors.accent, SonusCinematicColors.baseAccent);
  });

  test('no artwork gives the untinted cinematic base', () {
    final colors = SonusCinematicColors.resolve(
      decoration: decorationFor(const SonusAppearanceSpec()),
    );

    expect(colors.isTinted, isFalse);
    expect(colors.background, SonusCinematicColors.baseBackground);
    expect(colors.surface, SonusCinematicColors.baseSurface);
    expect(colors.accent, SonusCinematicColors.baseAccent);
  });

  group('accessibility settings take precedence', () {
    for (final (name, spec) in const [
      ('High contrast', SonusAppearanceSpec(highContrast: true)),
      ('Low effects', SonusAppearanceSpec(lowEffects: true)),
      (
        'Decoration Off',
        SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
    ]) {
      test('$name: flat, untinted, no glow, solid edge', () {
        final colors = SonusCinematicColors.resolve(
          decoration: decorationFor(spec),
          artwork: artworks['vibrant pink'],
        );

        expect(colors.isTinted, isFalse);
        expect(colors.background, SonusCinematicColors.baseBackground);
        expect(colors.hasGlow, isFalse);
        expect(colors.edge, SonusCinematicColors.baseTextSecondary);
        expect(colors.accent, SonusCinematicColors.baseAccent);
      });
    }
  });

  test('dark in every theme, Daylight included (D3)', () {
    final results = {
      for (final id in SonusThemeId.values)
        id: SonusCinematicColors.resolve(
          decoration: decorationFor(SonusAppearanceSpec(themeId: id)),
          artwork: artworks['midnight blue'],
        ),
    };

    for (final MapEntry(key: id, value: colors) in results.entries) {
      expect(
        colors.background.computeLuminance(),
        lessThan(0.05),
        reason: '${id.label} stays dark',
      );
    }
  });

  test(
    'lerp ends at its endpoints and never blends the text on the accent',
    () {
      final decoration = decorationFor(const SonusAppearanceSpec());
      final a = SonusCinematicColors.resolve(decoration: decoration);
      final b = SonusCinematicColors.resolve(
        decoration: decoration,
        artwork: artworks['bright yellow'],
      );

      expect(SonusCinematicColors.lerp(a, b, 0), a);
      expect(SonusCinematicColors.lerp(a, b, 1), b);
      expect(
        SonusCinematicColors.lerp(a, b, 0.4).onAccent,
        anyOf(a.onAccent, b.onAccent),
      );
    },
  );

  group('SonusCinematicAtmosphereBuilder', () {
    Future<List<SonusCinematicColors>> pump(
      WidgetTester tester,
      _FakePalette palette, {
      SonusAppearanceSpec spec = const SonusAppearanceSpec(
        themeId: SonusThemeId.daylight,
      ),
    }) async {
      final seen = <SonusCinematicColors>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(spec),
          home: SonusCinematicAtmosphereBuilder(
            artworkPath: '/pink.jpg',
            palette: palette,
            builder: (context, colors) {
              seen.add(colors);
              return const SizedBox();
            },
          ),
        ),
      );
      return seen;
    }

    testWidgets('asks for dark-background colours even in Daylight', (
      tester,
    ) async {
      final palette = _FakePalette({'/pink.jpg': artworks['vibrant pink']});
      final seen = await pump(tester, palette);
      await tester.pumpAndSettle();

      expect(palette.brightnesses, [Brightness.dark]);
      expect(seen.first.isTinted, isFalse, reason: 'base colours at once');
      expect(seen.last.isTinted, isTrue);
      expect(seen.last.background.computeLuminance(), lessThan(0.05));
    });

    testWidgets('eases in, and jumps with reduced motion', (tester) async {
      final eased = await pump(
        tester,
        _FakePalette({'/pink.jpg': artworks['vibrant pink']}),
      );
      await tester.pumpAndSettle();
      expect(eased.length, greaterThan(3), reason: 'several in-between frames');

      await tester.pumpWidget(const SizedBox());
      final reduced = await pump(
        tester,
        _FakePalette({'/pink.jpg': artworks['vibrant pink']}),
        spec: const SonusAppearanceSpec(
          themeId: SonusThemeId.daylight,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      final distinct = reduced.toSet();
      expect(distinct.length, 2, reason: 'base, then the final colours');
    });
  });
}

class _FakePalette extends SonusArtworkPalette {
  _FakePalette(this.colours);

  final Map<String?, SonusArtworkColors?> colours;
  final brightnesses = <Brightness>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    brightnesses.add(brightness);
    return colours[artworkPath];
  }
}
