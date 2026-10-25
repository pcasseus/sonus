import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

// SN-48J J5: artwork colours for album atmosphere.
void main() {
  (SonusColors, SonusDecorationTokens) themeFor(SonusAppearanceSpec spec) {
    final theme = SonusThemeFactory.build(spec);
    return (
      theme.extension<SonusColors>()!,
      theme.extension<SonusDecorationTokens>()!,
    );
  }

  const red = SonusArtworkColors(
    accent: Color(0xFFFF8A80),
    container: Color(0xFF8C1D18),
  );

  group('SonusArtworkAtmosphere', () {
    test('Decoration Off keeps the theme untouched', () {
      final (colors, decoration) = themeFor(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      );
      final atmosphere = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: red,
      );

      expect(atmosphere.isTinted, isFalse);
      expect(atmosphere.background, colors.background);
      expect(atmosphere.surface, colors.surface);
      expect(atmosphere.accent, colors.accentPrimary);
    });

    for (final (label, spec) in [
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
      test('$label keeps the theme colours for readability', () {
        final (colors, decoration) = themeFor(spec);
        final atmosphere = SonusArtworkAtmosphere.resolve(
          colors: colors,
          decoration: decoration,
          artwork: red,
        );

        expect(atmosphere.isTinted, isFalse);
        expect(atmosphere.background, colors.background);
        expect(atmosphere.accent, colors.accentPrimary);
      });
    }

    test('missing artwork falls back to the theme', () {
      final (colors, decoration) = themeFor(const SonusAppearanceSpec());
      final atmosphere = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
      );

      expect(atmosphere.isTinted, isFalse);
      expect(atmosphere.background, colors.background);
      expect(atmosphere.onAccent, colors.onAccentPrimary);
    });

    test('tint grows from Subtle to Standard to Expressive', () {
      final strengths = [
        for (final intensity in [
          SonusDecorationIntensity.subtle,
          SonusDecorationIntensity.standard,
          SonusDecorationIntensity.expressive,
        ])
          () {
            final (colors, decoration) = themeFor(
              SonusAppearanceSpec(decoration: intensity),
            );
            return SonusArtworkAtmosphere.resolve(
              colors: colors,
              decoration: decoration,
              artwork: red,
            ).strength;
          }(),
      ];

      expect(strengths.every((strength) => strength > 0), isTrue);
      expect(strengths[0], lessThan(strengths[1]));
      expect(strengths[1], lessThan(strengths[2]));
    });

    test('Standard tints toward the artwork and uses its accent', () {
      final (colors, decoration) = themeFor(const SonusAppearanceSpec());
      final atmosphere = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: red,
      );

      expect(atmosphere.isTinted, isTrue);
      expect(atmosphere.background, isNot(colors.background));
      // Moved toward the artwork's red.
      expect(
        (atmosphere.background.r - atmosphere.background.b),
        greaterThan(colors.background.r - colors.background.b),
      );
      expect(atmosphere.accent, red.accent);
    });

    test('Subtle tints the page but keeps the theme accent', () {
      final (colors, decoration) = themeFor(
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.subtle),
      );
      final atmosphere = SonusArtworkAtmosphere.resolve(
        colors: colors,
        decoration: decoration,
        artwork: red,
      );

      expect(atmosphere.isTinted, isTrue);
      expect(atmosphere.accent, colors.accentPrimary);
    });

    // Extreme artwork on every theme and level: text stays readable and the
    // accent stays distinct.
    const extremes = {
      'white': SonusArtworkColors(
        accent: Color(0xFFFFFFFF),
        container: Color(0xFFFFFFFF),
      ),
      'black': SonusArtworkColors(
        accent: Color(0xFF000000),
        container: Color(0xFF000000),
      ),
      'saturated yellow': SonusArtworkColors(
        accent: Color(0xFFFFEB3B),
        container: Color(0xFFFFD600),
      ),
      'saturated blue': SonusArtworkColors(
        accent: Color(0xFF2962FF),
        container: Color(0xFF0D47A1),
      ),
      'red': red,
    };

    for (final id in SonusThemeId.values) {
      test('${id.label} keeps contrast with extreme artwork', () {
        for (final intensity in SonusDecorationIntensity.values) {
          final (colors, decoration) = themeFor(
            SonusAppearanceSpec(themeId: id, decoration: intensity),
          );
          for (final MapEntry(key: name, value: artwork) in extremes.entries) {
            final atmosphere = SonusArtworkAtmosphere.resolve(
              colors: colors,
              decoration: decoration,
              artwork: artwork,
            );
            final reason = '${id.label}, ${intensity.label}, $name';

            for (final (text, ground, tinted) in [
              (colors.textPrimary, colors.background, atmosphere.background),
              (colors.textSecondary, colors.background, atmosphere.background),
              (colors.textPrimary, colors.surface, atmosphere.surface),
              (colors.textSecondary, colors.surface, atmosphere.surface),
            ]) {
              final required = SonusContrast.ratio(
                text,
                ground,
              ).clamp(1.0, 4.5);
              expect(
                SonusContrast.ratio(text, tinted),
                greaterThanOrEqualTo(required - 0.001),
                reason: reason,
              );
            }

            if (atmosphere.accent != colors.accentPrimary) {
              expect(
                SonusContrast.ratio(atmosphere.accent, atmosphere.background),
                greaterThanOrEqualTo(3),
                reason: reason,
              );
              expect(
                SonusContrast.ratio(atmosphere.accent, atmosphere.surface),
                greaterThanOrEqualTo(3),
                reason: reason,
              );
              expect(
                SonusContrast.ratio(atmosphere.onAccent, atmosphere.accent),
                greaterThanOrEqualTo(4.5),
                reason: reason,
              );
            }
          }
        }
      });
    }
  });

  group('SonusArtworkPalette cache', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sonus_palette_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String> file(
      String name, [
      List<int> bytes = const [1, 2, 3],
    ]) async {
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    test('no path or a missing file uses the theme without decoding', () async {
      var calls = 0;
      final palette = SonusArtworkPalette(
        extractor: (image, brightness) async {
          calls++;
          return red;
        },
      );

      expect(
        await palette.colorsFor(null, brightness: Brightness.dark),
        isNull,
      );
      expect(
        await palette.colorsFor('  ', brightness: Brightness.dark),
        isNull,
      );
      expect(
        await palette.colorsFor(
          '${dir.path}/missing.png',
          brightness: Brightness.dark,
        ),
        isNull,
      );
      expect(calls, 0);
    });

    test('decodes at the small size, never at full resolution', () async {
      ImageProvider? received;
      final palette = SonusArtworkPalette(
        decodeWidth: 96,
        extractor: (image, brightness) async {
          received = image;
          return red;
        },
      );

      await palette.colorsFor(await file('a.png'), brightness: Brightness.dark);

      expect(received, isA<ResizeImage>());
      expect((received! as ResizeImage).width, 96);
    });

    test('repeated and concurrent requests extract once', () async {
      var calls = 0;
      final palette = SonusArtworkPalette(
        extractor: (image, brightness) async {
          calls++;
          return red;
        },
      );
      final path = await file('a.png');

      final results = await Future.wait([
        palette.colorsFor(path, brightness: Brightness.dark),
        palette.colorsFor(path, brightness: Brightness.dark),
      ]);
      await palette.colorsFor(path, brightness: Brightness.dark);

      expect(results, everyElement(red));
      expect(calls, 1);
    });

    test('a replaced cover is extracted again', () async {
      var calls = 0;
      final palette = SonusArtworkPalette(
        extractor: (image, brightness) async {
          calls++;
          return red;
        },
      );
      final path = await file('a.png');

      await palette.colorsFor(path, brightness: Brightness.dark);
      await File(path).writeAsBytes(const [9, 9, 9, 9, 9, 9]);
      await palette.colorsFor(path, brightness: Brightness.dark);

      expect(calls, 2);
    });

    test('brightness is part of the cache key', () async {
      var calls = 0;
      final palette = SonusArtworkPalette(
        extractor: (image, brightness) async {
          calls++;
          return red;
        },
      );
      final path = await file('a.png');

      await palette.colorsFor(path, brightness: Brightness.dark);
      await palette.colorsFor(path, brightness: Brightness.light);

      expect(calls, 2);
    });

    test('the least recently used artwork is evicted', () async {
      final requested = <String>[];
      final palette = SonusArtworkPalette(
        capacity: 2,
        extractor: (image, brightness) async {
          final key = (image as ResizeImage).imageProvider as FileImage;
          requested.add(key.file.path.split(RegExp(r'[\\/]')).last);
          return red;
        },
      );
      final a = await file('a.png');
      final b = await file('b.png');
      final c = await file('c.png');

      await palette.colorsFor(a, brightness: Brightness.dark);
      await palette.colorsFor(b, brightness: Brightness.dark);
      await palette.colorsFor(a, brightness: Brightness.dark); // a is recent
      await palette.colorsFor(c, brightness: Brightness.dark); // evicts b
      await palette.colorsFor(a, brightness: Brightness.dark);
      await palette.colorsFor(b, brightness: Brightness.dark);

      expect(requested, ['a.png', 'b.png', 'c.png', 'b.png']);
      expect(palette.cachedCount, 2);
    });

    test('an extraction failure falls back to the theme', () async {
      final palette = SonusArtworkPalette(
        extractor: (image, brightness) async =>
            throw StateError('decoder failed'),
      );

      expect(
        await palette.colorsFor(
          await file('a.png'),
          brightness: Brightness.dark,
        ),
        isNull,
      );
    });
  });

  group('SonusArtworkPalette extraction', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sonus_palette_real');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String> png(String name, void Function(Canvas, double) paint) async {
      const size = 400;
      final recorder = ui.PictureRecorder();
      paint(Canvas(recorder), size.toDouble());
      final image = await recorder.endRecording().toImage(size, size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      return f.path;
    }

    void fill(Canvas canvas, double size, Color colour) => canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = colour,
    );

    testWidgets('a saturated cover yields its own hue', (tester) async {
      await tester.runAsync(() async {
        final path = await png('red.png', (canvas, size) {
          fill(canvas, size, const Color(0xFFD32F2F));
        });
        final colors = await SonusArtworkPalette().colorsFor(
          path,
          brightness: Brightness.dark,
        );

        expect(colors, isNotNull);
        final hue = HSLColor.fromColor(colors!.accent).hue;
        expect(hue < 25 || hue > 335, isTrue, reason: 'hue $hue');
      });
    });

    for (final (name, colour) in [
      ('white', const Color(0xFFFFFFFF)),
      ('black', const Color(0xFF000000)),
      ('grey', const Color(0xFF808080)),
    ]) {
      testWidgets('a $name cover has no colour to borrow, not a stock blue', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final path = await png('$name.png', (canvas, size) {
            fill(canvas, size, colour);
          });

          expect(
            await SonusArtworkPalette().colorsFor(
              path,
              brightness: Brightness.dark,
            ),
            isNull,
          );
        });
      });
    }

    testWidgets('a greyscale photo with a little colour stays neutral', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final path = await png('mono.png', (canvas, size) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size, size),
            Paint()
              ..shader = ui.Gradient.linear(Offset.zero, Offset(size, size), [
                const Color(0xFF111111),
                const Color(0xFFEEEEEE),
              ]),
          );
          // About 1% of the area in colour.
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size * 0.1, size * 0.1),
            Paint()..color = const Color(0xFF1E88E5),
          );
        });

        expect(
          await SonusArtworkPalette().colorsFor(
            path,
            brightness: Brightness.dark,
          ),
          isNull,
        );
      });
    });

    testWidgets('a corrupt file falls back to the theme', (tester) async {
      await tester.runAsync(() async {
        final f = File('${dir.path}/corrupt.png');
        await f.writeAsBytes(List<int>.generate(512, (i) => (i * 37) % 256));

        expect(
          await SonusArtworkPalette().colorsFor(
            f.path,
            brightness: Brightness.dark,
          ),
          isNull,
        );
      });
    });
  });
}
