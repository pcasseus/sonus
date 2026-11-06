import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'artwork/sonus_artwork_tint.dart';
import 'sonus_artwork_palette.dart';
import 'sonus_contrast.dart';
import 'sonus_tokens.dart';

/// The colours of Sonus's cinematic screens (the artist Film Reel and
/// Roster, UI redesign D3): always dark and artwork-driven, whatever the
/// theme, including Daylight. Unlike [SonusArtworkAtmosphere], which nudges
/// the user's theme, these replace it, so they carry their own text colours.
///
/// Accessibility comes first. Where gradients are not allowed (Decoration
/// Off, High contrast, Low effects) the colours are flat and untinted, with
/// no glow and a solid, visible edge. Tinted or not:
/// - [textPrimary] keeps at least 7:1 and [textSecondary] at least 4.5:1
///   against both [background] and [surface];
/// - [accent] keeps at least 3:1 against both, and [onAccent] at least
///   4.5:1 on the accent.
@immutable
class SonusCinematicColors {
  const SonusCinematicColors({
    required this.background,
    required this.backgroundDeep,
    required this.surface,
    required this.edge,
    required this.glow,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.strength,
  });

  /// Resolves the cinematic colours for [artwork] (extracted for a dark
  /// background) under [decoration].
  factory SonusCinematicColors.resolve({
    required SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
  }) {
    final flat = !decoration.allowGradients;
    final target = artwork == null || flat
        ? 0.0
        : strengthFor(decoration.intensity);

    final strength = SonusArtworkTint.strongestReadable(
      target,
      (strength) => _readable(artwork!, strength),
    );

    final background = artwork == null || strength == 0
        ? baseBackground
        : _tint(baseBackground, artwork, strength);
    final surface = artwork == null || strength == 0
        ? baseSurface
        : _tint(baseSurface, artwork, strength * 0.8);
    final backgroundDeep = artwork == null || strength == 0
        ? baseBackgroundDeep
        : _tint(baseBackgroundDeep, artwork, strength * 0.6);

    final accent = _accent(decoration, artwork, background, surface);
    final glow = decoration.allowGlow && !flat
        ? accent.withValues(alpha: 0.45)
        : const Color(0x00000000);

    return SonusCinematicColors(
      background: background,
      backgroundDeep: backgroundDeep,
      surface: surface,
      // A light, accent-tinted rim reads as glass; flat colours get a solid
      // border that is easy to see.
      edge: flat
          ? baseTextSecondary
          : Color.lerp(const Color(0x38FFFFFF), accent, 0.35)!,
      glow: glow,
      accent: accent,
      onAccent: SonusArtworkTint.onColour(accent),
      textPrimary: baseTextPrimary,
      textSecondary: baseTextSecondary,
      strength: strength,
    );
  }

  /// The untinted cinematic base, deep violet-black.
  static const Color baseBackground = Color(0xFF0B0911);
  static const Color baseBackgroundDeep = Color(0xFF050408);
  static const Color baseSurface = Color(0xFF19151F);
  static const Color baseTextPrimary = Color(0xFFF5F2FA);
  static const Color baseTextSecondary = Color(0xFFC4BCD3);

  /// The accent when the artwork offers none that stays legible.
  static const Color baseAccent = Color(0xFFB78CFF);

  /// Page background at the top, and toward the bottom of its gradient.
  final Color background;
  final Color backgroundDeep;

  /// The base of glass panels and cards.
  final Color surface;

  /// Panel rims and outlines.
  final Color edge;

  /// Glow around the selected portrait and panels; transparent when glow
  /// is not allowed.
  final Color glow;

  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;

  /// How strongly the artwork tints the base, from 0 (not at all) to 1.
  final double strength;

  bool get isTinted => strength > 0;

  bool get hasGlow => glow.a > 0;

  /// Tint strength for each Decoration level. Stronger than the theme
  /// atmosphere's: the base is near-black, so more colour is needed for
  /// the artwork to come through.
  static double strengthFor(SonusDecorationIntensity intensity) =>
      switch (intensity) {
        SonusDecorationIntensity.off => 0,
        SonusDecorationIntensity.subtle => 0.22,
        SonusDecorationIntensity.standard => 0.34,
        SonusDecorationIntensity.expressive => 0.46,
      };

  static Color _tint(Color base, SonusArtworkColors artwork, double amount) =>
      SonusArtworkTint.tint(base, artwork, amount);

  static bool _readable(SonusArtworkColors artwork, double strength) {
    for (final ground in [
      _tint(baseBackground, artwork, strength),
      _tint(baseSurface, artwork, strength * 0.8),
    ]) {
      if (SonusContrast.ratio(baseTextPrimary, ground) < 7) return false;
      if (SonusContrast.ratio(baseTextSecondary, ground) < 4.5) return false;
    }
    return true;
  }

  static Color _accent(
    SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
    Color background,
    Color surface,
  ) {
    final candidate = artwork?.accent;
    if (candidate == null ||
        !decoration.allowGradients ||
        decoration.intensity == SonusDecorationIntensity.subtle) {
      return baseAccent;
    }
    return SonusArtworkTint.distinctAccent(candidate, [
      background,
      surface,
    ], fallback: baseAccent);
  }

  static SonusCinematicColors lerp(
    SonusCinematicColors a,
    SonusCinematicColors b,
    double t,
  ) {
    return SonusCinematicColors(
      background: Color.lerp(a.background, b.background, t)!,
      backgroundDeep: Color.lerp(a.backgroundDeep, b.backgroundDeep, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      edge: Color.lerp(a.edge, b.edge, t)!,
      glow: Color.lerp(a.glow, b.glow, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      // Switches rather than blends, so it never passes through a
      // low-contrast midpoint.
      onAccent: t < 0.5 ? a.onAccent : b.onAccent,
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
      strength: a.strength + (b.strength - a.strength) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SonusCinematicColors &&
      other.background == background &&
      other.backgroundDeep == backgroundDeep &&
      other.surface == surface &&
      other.edge == edge &&
      other.glow == glow &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(
    background,
    backgroundDeep,
    surface,
    edge,
    glow,
    accent,
    onAccent,
    textPrimary,
    textSecondary,
    strength,
  );
}

class SonusCinematicColorsTween extends Tween<SonusCinematicColors> {
  SonusCinematicColorsTween({super.end});

  @override
  SonusCinematicColors lerp(double t) =>
      SonusCinematicColors.lerp(begin!, end!, t);
}
