import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'sonus_artwork_palette.dart';
import 'sonus_atmosphere_colors.dart';
import 'sonus_contrast.dart';
import 'sonus_tokens.dart';

/// The colours of the Artist and Album Profiles (UI redesign P1, P2, D3):
/// the user's theme, light or dark, taken over by the artwork's own colour.
/// Midnight-blue artwork gives a blue page, vibrant pink a pink one. It is
/// stronger than [SonusArtworkAtmosphere], which only nudges the theme for
/// quieter screens such as the queue and lyrics.
///
/// The artwork's colours are extracted for the theme's brightness, so a
/// dark theme gets deep tones and a light theme pale ones. The page runs
/// from [background] at the top to [backgroundDeep], closer to the theme,
/// lower down. Glass sections sit on [surface] with an [edge] rim.
///
/// Accessibility comes first:
/// - Where gradients are not allowed (Decoration Off, High contrast, Low
///   effects) the colours are the theme's, flat, with no glow.
/// - The tint weakens until the theme's text keeps its contrast on every
///   ground, including glass: at least 4.5:1, or never less than the
///   theme itself offers.
/// - The accent keeps at least 3:1 against every ground, or the theme's
///   accent is used.
@immutable
class SonusProfileColors {
  const SonusProfileColors({
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

  /// Resolves the profile colours for [artwork] (extracted for the theme's
  /// brightness) on the theme [colors] under [decoration].
  factory SonusProfileColors.resolve({
    required SonusColors colors,
    required SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
  }) {
    final flat = !decoration.allowGradients;
    final target = artwork == null || flat
        ? 0.0
        : strengthFor(decoration.intensity);

    var strength = target;
    while (strength > 0 && !_readable(colors, artwork!, strength)) {
      strength = (strength - 0.02).clamp(0.0, 1.0);
    }

    final tinted = artwork != null && strength > 0;
    final background = tinted
        ? _tint(colors.background, artwork, strength)
        : colors.background;
    final backgroundDeep = tinted
        ? _tint(colors.background, artwork, strength * deepShare)
        : colors.background;
    final surface = tinted
        ? _tint(colors.surface, artwork, strength * surfaceShare)
        : colors.surface;

    final accent = _accent(colors, decoration, tinted ? artwork : null, [
      background,
      backgroundDeep,
      surface,
      ..._glassGrounds(surface, background, backgroundDeep),
    ]);
    final onAccent = accent == colors.accentPrimary
        ? colors.onAccentPrimary
        : _onColour(accent);

    return SonusProfileColors(
      background: background,
      backgroundDeep: backgroundDeep,
      surface: surface,
      edge: flat || !tinted
          ? colors.border
          : Color.lerp(colors.border, accent, 0.4)!,
      glow: decoration.allowGlow && tinted
          ? accent.withValues(alpha: 0.30)
          : const Color(0x00000000),
      accent: accent,
      onAccent: onAccent,
      textPrimary: colors.textPrimary,
      textSecondary: colors.textSecondary,
      strength: tinted ? strength : 0,
    );
  }

  /// The page at the top, under the hero.
  final Color background;

  /// The page lower down: the tint fades toward the theme.
  final Color backgroundDeep;

  /// The base of glass sections and cards.
  final Color surface;

  /// Rims of glass sections.
  final Color edge;

  /// Glow around the portrait and accents; transparent where glow is not
  /// allowed or there is no tint.
  final Color glow;

  final Color accent;
  final Color onAccent;

  /// The theme's text colours, readable on every ground above.
  final Color textPrimary;
  final Color textSecondary;

  /// How strongly the artwork tints the theme, from 0 (not at all) to 1.
  final double strength;

  bool get isTinted => strength > 0;

  bool get hasGlow => glow.a > 0;

  /// The same colours for widgets that take the quieter atmosphere type.
  SonusAtmosphereColors get atmosphere => SonusAtmosphereColors(
    background: background,
    surface: surface,
    accent: accent,
    onAccent: onAccent,
    isTinted: isTinted,
  );

  /// How much of the tint reaches the bottom of the page, and the glass.
  static const double deepShare = 0.45;
  static const double surfaceShare = 0.85;

  /// Tint strength for each Decoration level: enough for the artwork's
  /// colour to carry the page.
  static double strengthFor(SonusDecorationIntensity intensity) =>
      switch (intensity) {
        SonusDecorationIntensity.off => 0,
        SonusDecorationIntensity.subtle => 0.22,
        SonusDecorationIntensity.standard => 0.38,
        SonusDecorationIntensity.expressive => 0.52,
      };

  static Color _tint(Color base, SonusArtworkColors artwork, double amount) =>
      Color.lerp(base, artwork.container, amount)!;

  /// What text on a glass section actually sits on: SonusGlassPanel's
  /// light top-left and clearer bottom-right, over the page.
  static List<Color> _glassGrounds(
    Color surface,
    Color background,
    Color backgroundDeep,
  ) => [
    Color.alphaBlend(
      Color.lerp(
        surface,
        const Color(0xFFFFFFFF),
        0.10,
      )!.withValues(alpha: 0.74),
      background,
    ),
    Color.alphaBlend(surface.withValues(alpha: 0.56), backgroundDeep),
    Color.alphaBlend(surface.withValues(alpha: 0.56), background),
  ];

  static bool _readable(
    SonusColors colors,
    SonusArtworkColors artwork,
    double strength,
  ) {
    final background = _tint(colors.background, artwork, strength);
    final deep = _tint(colors.background, artwork, strength * deepShare);
    final surface = _tint(colors.surface, artwork, strength * surfaceShare);
    final grounds = [
      (colors.background, background),
      (colors.background, deep),
      (colors.surface, surface),
      for (final glass in _glassGrounds(surface, background, deep))
        (colors.surface, glass),
    ];
    for (final text in [colors.textPrimary, colors.textSecondary]) {
      for (final (themeGround, tinted) in grounds) {
        final required = SonusContrast.ratio(text, themeGround).clamp(1.0, 4.5);
        if (SonusContrast.ratio(text, tinted) < required) return false;
      }
    }
    return true;
  }

  static Color _accent(
    SonusColors colors,
    SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
    List<Color> grounds,
  ) {
    // Subtle keeps the theme's own accent: blending two unrelated hues
    // gives a muddy colour, so only the grounds are tinted.
    if (artwork == null ||
        !decoration.allowGradients ||
        decoration.intensity == SonusDecorationIntensity.subtle) {
      return colors.accentPrimary;
    }
    final candidate = artwork.accent;
    final distinct = grounds.every(
      (ground) => SonusContrast.ratio(candidate, ground) >= 3,
    );
    return distinct ? candidate : colors.accentPrimary;
  }

  /// Black or white, whichever reads better on [colour] (always ≥ 4.5:1).
  static Color _onColour(Color colour) {
    const dark = Color(0xFF000000);
    const light = Color(0xFFFFFFFF);
    return SonusContrast.ratio(dark, colour) >=
            SonusContrast.ratio(light, colour)
        ? dark
        : light;
  }

  static SonusProfileColors lerp(
    SonusProfileColors a,
    SonusProfileColors b,
    double t,
  ) {
    return SonusProfileColors(
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
      other is SonusProfileColors &&
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

class SonusProfileColorsTween extends Tween<SonusProfileColors> {
  SonusProfileColorsTween({super.end});

  @override
  SonusProfileColors lerp(double t) => SonusProfileColors.lerp(begin!, end!, t);
}
