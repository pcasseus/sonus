import 'package:flutter/material.dart';

import 'sonus_theme_id.dart';

/// Raw colours of one theme. Screens never read these directly; the theme
/// factory maps them onto [ColorScheme] roles and semantic tokens.
@immutable
class SonusPalette {
  const SonusPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.raisedSurface,
    required this.neutral,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.text,
    required this.secondaryText,
    required this.divider,
    required this.error,
    required this.chartUp,
    required this.chartDown,
  });

  final Brightness brightness;

  /// Page background.
  final Color background;

  /// Cards and grouped content.
  final Color surface;

  /// Raised elements such as the mini-player and selected tiles.
  final Color raisedSurface;

  /// Muted structural colour (e.g. Concrete & Spray's concrete gray). Used
  /// for inactive tracks and placeholders, never for text.
  final Color neutral;

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color text;
  final Color secondaryText;
  final Color divider;
  final Color error;

  /// Chart movement colours. Always paired with an icon or label, so
  /// movement is never conveyed by colour alone.
  final Color chartUp;
  final Color chartDown;
}

/// The decorative vocabulary a theme draws with.
enum SonusMotif {
  /// Concrete & Spray: restrained spray marks with a short drip.
  spray,

  /// Kickflip: sticker edges and tape.
  sticker,

  /// After Hours: thin light trails.
  lightTrail,

  /// Y2K Replay: chrome-like gradient bars.
  chrome,

  /// Neon Mixtape: neon outlines.
  neon,

  /// 2017 Haze: soft atmospheric blur.
  haze,

  /// Monochrome: solid geometric blocks.
  geometric,

  /// Daylight: fine editorial rules.
  editorial,

  /// Evergreen: organic curves.
  organic,
}

/// Playback progress treatments (Revision 9, section 11). Every style is a
/// visual treatment over the same linear seek contract; SN-48E renders them.
enum SonusProgressStyle {
  sprayWave,
  tapeStrip,
  frequencyBars,
  softWave,
  chromeLinear,
  minimalLinear,
}

/// Everything that makes one theme distinct. All themes share the same
/// screens; nothing here may change features, data or navigation.
@immutable
class SonusThemeDefinition {
  const SonusThemeDefinition({
    required this.id,
    required this.identity,
    required this.palette,
    required this.motif,
    required this.progressStyle,
    required this.cardRadius,
    required this.artworkRadius,
    required this.hasTexture,
    required this.motionCurve,
  });

  final SonusThemeId id;

  /// One line describing the theme, shown in Appearance Settings.
  final String identity;
  final SonusPalette palette;
  final SonusMotif motif;
  final SonusProgressStyle progressStyle;
  final double cardRadius;
  final double artworkRadius;

  /// Whether Standard and Expressive decoration add a faint surface texture.
  final bool hasTexture;

  /// The easing that gives the theme its motion character.
  final Curve motionCurve;
}
