import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

void main() {
  group('catalog', () {
    test('defines every theme exactly once', () {
      final ids = SonusThemeCatalog.all.map((d) => d.id).toList();

      expect(ids, SonusThemeId.values);
    });

    test('storage keys are unique and stable', () {
      expect(SonusThemeId.values.map((id) => id.storageKey).toList(), [
        'concrete_spray',
        'kickflip',
        'after_hours',
        'y2k_replay',
        'neon_mixtape',
        'haze_2017',
        'monochrome',
        'daylight',
        'evergreen',
      ]);

      for (final id in SonusThemeId.values) {
        expect(SonusThemeId.fromStorageKey(id.storageKey), id);
      }

      expect(SonusThemeId.fromStorageKey('unknown'), isNull);
      expect(SonusThemeId.fromStorageKey(null), isNull);
    });

    test('Concrete & Spray is the default and uses the Revision 9 palette', () {
      expect(SonusThemeId.defaultTheme, SonusThemeId.concreteSpray);

      final palette = SonusThemeCatalog.of(SonusThemeId.concreteSpray).palette;

      expect(palette.background, const Color(0xFF17191D));
      expect(palette.surface, const Color(0xFF22252B));
      expect(palette.raisedSurface, const Color(0xFF2D3138));
      expect(palette.neutral, const Color(0xFF575D64));
      expect(palette.primary, const Color(0xFF398BFF));
      expect(palette.secondary, const Color(0xFFFF4F91));
      expect(palette.text, const Color(0xFFEDE9DF));
      expect(palette.secondaryText, const Color(0xFFADB2BA));
      expect(palette.divider, const Color(0xFF3B4048));
    });

    test('every theme is black-based', () {
      // Sonus is a black music app: light colours may be text and accents,
      // never the page or its main surfaces.
      for (final definition in SonusThemeCatalog.all) {
        final palette = definition.palette;
        final name = definition.id.label;

        expect(palette.brightness, Brightness.dark, reason: name);
        expect(
          palette.background.computeLuminance(),
          lessThan(0.015),
          reason: '$name background must be black or near-black',
        );
        for (final surface in [palette.surface, palette.raisedSurface]) {
          expect(
            surface.computeLuminance(),
            lessThan(0.05),
            reason: '$name surfaces must stay dark',
          );
        }
      }
    });

    test('every theme keeps a distinct background and accent pair', () {
      final pairs = {
        for (final definition in SonusThemeCatalog.all)
          (definition.palette.background, definition.palette.primary),
      };

      expect(pairs, hasLength(SonusThemeId.values.length));
    });

    test('every theme has a distinct motif', () {
      final motifs = SonusThemeCatalog.all.map((d) => d.motif).toSet();

      expect(motifs, hasLength(SonusThemeId.values.length));
    });
  });

  // WCAG 2.2 AA: 4.5:1 for text, 3:1 for icons and UI components.
  for (final highContrast in [false, true]) {
    group(highContrast ? 'high-contrast tokens' : 'tokens', () {
      for (final definition in SonusThemeCatalog.all) {
        final colors = SonusThemeFactory.colorsFor(
          definition,
          highContrast: highContrast,
        );
        final surfaces = {
          'background': colors.background,
          'surface': colors.surface,
          'raisedSurface': colors.raisedSurface,
        };

        test('${definition.id.label} meets AA contrast', () {
          for (final MapEntry(key: name, value: surface) in surfaces.entries) {
            _expectContrast(colors.textPrimary, surface, 4.5, 'text on $name');
            _expectContrast(
              colors.textSecondary,
              surface,
              4.5,
              'secondary text on $name',
            );
            _expectContrast(colors.border, surface, 3, 'border on $name');
            _expectContrast(colors.focus, surface, 3, 'focus on $name');
            _expectContrast(
              colors.accentPrimary,
              surface,
              3,
              'primary accent on $name',
            );
            _expectContrast(colors.chartUp, surface, 3, 'chart up on $name');
            _expectContrast(
              colors.chartDown,
              surface,
              3,
              'chart down on $name',
            );
          }

          _expectContrast(
            colors.onAccentPrimary,
            colors.accentPrimary,
            4.5,
            'label on primary accent',
          );
          _expectContrast(
            colors.onPlaybackControl,
            colors.playbackControl,
            4.5,
            'icon on playback control',
          );
          _expectContrast(
            colors.onArtworkPlaceholder,
            colors.artworkPlaceholder,
            3,
            'icon on artwork placeholder',
          );
          _expectContrast(
            colors.progressActive,
            colors.raisedSurface,
            3,
            'progress on the mini-player',
          );
        });
      }
    });
  }

  test('high contrast never weakens secondary text or borders', () {
    for (final definition in SonusThemeCatalog.all) {
      final normal = SonusThemeFactory.colorsFor(
        definition,
        highContrast: false,
      );
      final strong = SonusThemeFactory.colorsFor(
        definition,
        highContrast: true,
      );

      for (final surface in [normal.background, normal.surface]) {
        expect(
          SonusContrast.ratio(strong.textSecondary, surface),
          greaterThanOrEqualTo(
            SonusContrast.ratio(normal.textSecondary, surface),
          ),
          reason: definition.id.label,
        );
        expect(
          SonusContrast.ratio(strong.border, surface),
          greaterThanOrEqualTo(SonusContrast.ratio(normal.border, surface)),
          reason: definition.id.label,
        );
      }
    }
  });

  test('chart movement colours differ from each other in every theme', () {
    // Colour is never the only signal (icons carry movement too), but up and
    // down must still be distinguishable.
    for (final definition in SonusThemeCatalog.all) {
      final SonusColors colors = SonusThemeFactory.colorsFor(
        definition,
        highContrast: false,
      );

      expect(colors.chartUp, isNot(colors.chartDown));
    }
  });
}

void _expectContrast(
  Color foreground,
  Color background,
  double min,
  String what,
) {
  final ratio = SonusContrast.ratio(foreground, background);

  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what is ${ratio.toStringAsFixed(2)}:1, needs $min:1',
  );
}
