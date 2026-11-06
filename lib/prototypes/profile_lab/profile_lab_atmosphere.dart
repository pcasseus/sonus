// Artist Profile Lab: the colours of one page, derived from its artwork.
//
// PROTOTYPE ONLY (see profile_lab_models.dart).
//
// The method differs from the production profile colours on purpose:
// - the page is not one tint clamped dark enough for the worst pixel; it is
//   a lit environment (ground, two lights, a deep corner tone) and text
//   gets its own local ground (glass plates and scrims, profile_lab_page);
// - the artwork's hue sets the light, its chroma is kept moderate (no
//   saturation boost), and neutral or near-white artwork gets a silver
//   environment instead of a forced colour.
import 'package:flutter/material.dart';

import '../../core/design/sonus_artwork_palette.dart';
import '../../core/design/sonus_contrast.dart';
import '../../core/design/sonus_tokens.dart';

/// Which layers the page draws; every one can be switched off to measure
/// or compare it. [all] is the page as designed.
@immutable
class LabLayers {
  const LabLayers({
    this.backdropImage = true,
    this.lights = true,
    this.scrims = true,
    this.glass = true,
    this.heroPhoto = true,
    this.thumbnails = true,
    this.ink = true,
  });

  static const LabLayers all = LabLayers();

  /// Only the colour ground: what "no artwork at all" would look like.
  static const LabLayers groundOnly = LabLayers(
    backdropImage: false,
    lights: false,
    scrims: false,
    glass: false,
    heroPhoto: false,
    thumbnails: false,
  );

  /// The blurred, tone-mapped artwork behind the page.
  final bool backdropImage;

  /// Light pools, wisps and the vignette.
  final bool lights;

  /// Local grounds behind text that sits on the backdrop.
  final bool scrims;

  /// Glass plates (cards, chips, buttons).
  final bool glass;

  /// The sharp artist photo at the top.
  final bool heroPhoto;

  /// Track, release and collaboration pictures.
  final bool thumbnails;

  /// Text and icons. Off draws them transparent, with the same layout, so
  /// the ground under every word can be measured.
  final bool ink;

  LabLayers copyWith({
    bool? backdropImage,
    bool? lights,
    bool? scrims,
    bool? glass,
    bool? heroPhoto,
    bool? thumbnails,
    bool? ink,
  }) => LabLayers(
    backdropImage: backdropImage ?? this.backdropImage,
    lights: lights ?? this.lights,
    scrims: scrims ?? this.scrims,
    glass: glass ?? this.glass,
    heroPhoto: heroPhoto ?? this.heroPhoto,
    thumbnails: thumbnails ?? this.thumbnails,
    ink: ink ?? this.ink,
  );

  /// No imagery at all: the reference for the imagery-coverage measure.
  LabLayers get withoutImagery =>
      copyWith(backdropImage: false, heroPhoto: false, thumbnails: false);
}

/// The colours of one lab page.
@immutable
class LabAtmosphere {
  const LabAtmosphere({
    required this.effects,
    required this.highContrast,
    required this.neutral,
    required this.ground,
    required this.groundDeep,
    required this.light,
    required this.lightSecondary,
    required this.glass,
    required this.glassRim,
    required this.accentTop,
    required this.accentBottom,
    required this.onAccent,
    required this.accentLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  /// Lab colours for [artwork] (null: none, or artwork without colour) on
  /// the theme [colors]. Decoration Off, High contrast and Low effects get
  /// the flat theme page: no imagery behind content, no lights, solid
  /// plates.
  factory LabAtmosphere.resolve({
    required SonusColors colors,
    required SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
  }) {
    if (!decoration.allowGradients) {
      return LabAtmosphere(
        effects: false,
        highContrast: decoration.highContrast,
        neutral: artwork == null,
        ground: colors.background,
        groundDeep: colors.background,
        light: colors.accentPrimary,
        lightSecondary: colors.accentSecondary,
        glass: colors.surface,
        glassRim: decoration.highContrast
            ? colors.textSecondary
            : colors.border,
        accentTop: colors.accentPrimary,
        accentBottom: colors.accentPrimary,
        onAccent: colors.onAccentPrimary,
        accentLine: colors.accentPrimary,
        textPrimary: colors.textPrimary,
        textSecondary: decoration.highContrast
            ? colors.textPrimary
            : colors.textSecondary,
        border: decoration.highContrast ? colors.textSecondary : colors.border,
      );
    }

    final source = HSLColor.fromColor(artwork?.accent ?? colors.accentPrimary);
    // Neutral or near-white artwork: a silver environment that keeps a
    // trace of the theme's hue, never a colour the artwork does not have.
    final neutral = artwork == null || source.saturation < 0.12;
    final hue = source.hue;
    final chroma = neutral ? 0.10 : source.saturation.clamp(0.0, 0.62);

    Color tone(double lightness, {double chromaScale = 1, double shift = 0}) =>
        HSLColor.fromAHSL(
          1,
          (hue + shift) % 360,
          (chroma * chromaScale).clamp(0.0, 1.0),
          lightness,
        ).toColor();

    // Deep enough for a white label at 4.5:1; the glow keeps it luminous.
    final accentTop = tone(0.40, chromaScale: neutral ? 1.2 : 1.05);
    final accentBottom = tone(0.30, chromaScale: neutral ? 1.2 : 1.05);
    const white = Color(0xFFFFFFFF);
    const ink = Color(0xFF0B0D10);
    // The button label: white where it reads, else near-black.
    final onAccent =
        SonusContrast.ratio(white, accentTop) >= 4.5 &&
            SonusContrast.ratio(white, accentBottom) >= 4.5
        ? white
        : ink;

    return LabAtmosphere(
      effects: true,
      highContrast: false,
      neutral: neutral,
      ground: tone(0.085, chromaScale: 0.75),
      groundDeep: tone(0.035, chromaScale: 0.6),
      light: tone(0.62, chromaScale: 0.9),
      // An analogous second hue for depth, as light falling from another
      // direction; muted so the artwork's own colour leads.
      lightSecondary: tone(0.50, chromaScale: 0.7, shift: neutral ? 0 : 24),
      // Lighter than the backdrop it sits on, as frosted glass catching the
      // light (the reference's material), still dark enough for its text.
      // The plate's tint; LabGlass also lifts the backdrop under it.
      glass: tone(0.16, chromaScale: 0.55).withValues(alpha: 0.06),
      glassRim: white.withValues(alpha: 0.13),
      accentTop: accentTop,
      accentBottom: accentBottom,
      onAccent: onAccent,
      accentLine: tone(0.66, chromaScale: 1.0),
      textPrimary: const Color(0xFFF5F7FA),
      textSecondary: HSLColor.fromAHSL(1, hue, 0.14, 0.80).toColor(),
      border: white.withValues(alpha: 0.14),
    );
  }

  /// Imagery, lights, glow and translucent glass are drawn.
  final bool effects;
  final bool highContrast;

  /// The artwork had no colour worth following.
  final bool neutral;

  /// The page's base tone, and its deepest corners.
  final Color ground;
  final Color groundDeep;

  /// The main light, and a second, analogous one.
  final Color light;
  final Color lightSecondary;

  /// Glass plate fill and its lit rim.
  final Color glass;
  final Color glassRim;

  /// The Play button's gradient and label.
  final Color accentTop;
  final Color accentBottom;
  final Color onAccent;

  /// Section markers and the playing row.
  final Color accentLine;

  final Color textPrimary;
  final Color textSecondary;

  /// Hairlines between rows, and plate edges without effects.
  final Color border;

  /// The same page with every text and icon transparent (layout kept).
  LabAtmosphere get withoutInk => LabAtmosphere(
    effects: effects,
    highContrast: highContrast,
    neutral: neutral,
    ground: ground,
    groundDeep: groundDeep,
    light: light,
    lightSecondary: lightSecondary,
    glass: glass,
    glassRim: glassRim,
    accentTop: accentTop,
    accentBottom: accentBottom,
    onAccent: const Color(0x00000000),
    accentLine: accentLine,
    textPrimary: const Color(0x00000000),
    textSecondary: const Color(0x00000000),
    border: border,
  );
}
