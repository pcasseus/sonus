import 'package:flutter/material.dart';

/// User-selectable typography presets.
///
/// Presets only change display-level text: page and section headings,
/// featured statistics, chart ranks and important figures. Song, artist and
/// album names, menus, metadata and controls keep the readable base styles.
/// No fonts are bundled; Editorial uses the platform's serif family.
enum SonusTypographyPreset {
  streetBold('street_bold', 'Street Bold'),
  editorial('editorial', 'Editorial'),
  classicUi('classic_ui', 'Classic UI');

  const SonusTypographyPreset(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static const SonusTypographyPreset defaultPreset = streetBold;

  static SonusTypographyPreset? fromStorageKey(Object? key) {
    for (final value in values) {
      if (value.storageKey == key) {
        return value;
      }
    }

    return null;
  }
}

abstract final class SonusTypography {
  /// Platform serif families, tried in order. All are system fonts.
  static const editorialFamilyFallback = [
    'Georgia',
    'Times New Roman',
    'Noto Serif',
  ];

  /// Applies [preset] to the display levels of [base], coloured [color].
  ///
  /// Headings are moderately enlarged for Street Bold and Editorial. Sizes
  /// are logical sizes; system text scaling still applies on top.
  static TextTheme apply(
    TextTheme base,
    SonusTypographyPreset preset,
    Color color,
  ) {
    final colored = base.apply(bodyColor: color, displayColor: color);

    // ThemeData's text theme carries no sizes; Material adds them when the
    // theme is read. Headings changed here take their sizes from the
    // Material 3 geometry so they can be scaled. Untouched styles keep the
    // localized geometry.
    final geometry = Typography.material2021().englishLike;

    TextStyle heading(
      TextStyle? Function(TextTheme theme) pick, {
      required double scale,
      required FontWeight weight,
      required double letterSpacing,
      double? height,
    }) {
      // Geometry styles are non-inheriting; every style must stay
      // inheriting so themes and presets can be interpolated.
      final source = (pick(geometry) ?? const TextStyle())
          .copyWith(inherit: true)
          .merge(pick(colored));

      return source.copyWith(
        fontSize: source.fontSize == null ? null : source.fontSize! * scale,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        fontFamily: preset == SonusTypographyPreset.editorial ? 'serif' : null,
        fontFamilyFallback: preset == SonusTypographyPreset.editorial
            ? editorialFamilyFallback
            : null,
      );
    }

    return switch (preset) {
      SonusTypographyPreset.streetBold => colored.copyWith(
        displayLarge: heading(
          (t) => t.displayLarge,
          scale: 1.0,
          weight: FontWeight.w900,
          letterSpacing: -1.0,
          height: 1.05,
        ),
        displayMedium: heading(
          (t) => t.displayMedium,
          scale: 1.0,
          weight: FontWeight.w900,
          letterSpacing: -0.8,
          height: 1.05,
        ),
        displaySmall: heading(
          (t) => t.displaySmall,
          scale: 1.0,
          weight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.1,
        ),
        headlineLarge: heading(
          (t) => t.headlineLarge,
          scale: 1.08,
          weight: FontWeight.w900,
          letterSpacing: -0.6,
          height: 1.1,
        ),
        headlineMedium: heading(
          (t) => t.headlineMedium,
          scale: 1.08,
          weight: FontWeight.w900,
          letterSpacing: -0.5,
          height: 1.1,
        ),
        headlineSmall: heading(
          (t) => t.headlineSmall,
          scale: 1.06,
          weight: FontWeight.w800,
          letterSpacing: -0.3,
          height: 1.15,
        ),
        titleLarge: heading(
          (t) => t.titleLarge,
          scale: 1.06,
          weight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      SonusTypographyPreset.editorial => colored.copyWith(
        displayLarge: heading(
          (t) => t.displayLarge,
          scale: 1.0,
          weight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        displayMedium: heading(
          (t) => t.displayMedium,
          scale: 1.0,
          weight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        displaySmall: heading(
          (t) => t.displaySmall,
          scale: 1.0,
          weight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        headlineLarge: heading(
          (t) => t.headlineLarge,
          scale: 1.08,
          weight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        headlineMedium: heading(
          (t) => t.headlineMedium,
          scale: 1.08,
          weight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        headlineSmall: heading(
          (t) => t.headlineSmall,
          scale: 1.06,
          weight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: heading(
          (t) => t.titleLarge,
          scale: 1.06,
          weight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      SonusTypographyPreset.classicUi => colored.copyWith(
        headlineMedium: heading(
          (t) => t.headlineMedium,
          scale: 1.0,
          weight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineSmall: heading(
          (t) => t.headlineSmall,
          scale: 1.0,
          weight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleLarge: heading(
          (t) => t.titleLarge,
          scale: 1.0,
          weight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    };
  }
}
