import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/foundation.dart';

import 'artwork/sonus_artwork_tint.dart';
import 'sonus_artwork_palette.dart';
import 'sonus_atmosphere_colors.dart';
import 'sonus_tokens.dart';

/// The colours of the Artist and Album Profiles (UI redesign P1, P2, D3):
/// the user's theme, light or dark, taken over by the artwork's own colour.
/// Midnight-blue artwork gives a blue page, vibrant pink a pink one. It is
/// stronger than [SonusArtworkAtmosphere], which only nudges the theme for
/// quieter screens such as the queue and lyrics.
///
/// The artwork's colours are extracted for the theme's brightness, so a
/// dark theme gets deep tones and a light theme pale ones. The page runs
/// from [background] at the top to [backgroundDeep] lower down, still clearly the artwork's colour (V1: the atmosphere carries
/// the whole page), lit by soft pools of [light]. Glass sections sit on
/// [surface], translucent, with a faint [edge].
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
    required this.light,
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
    SonusArtworkTone tone = SonusArtworkTone.standard,
  }) {
    // The artwork's hue at a tone the page can carry (see [toneFor]).
    return SonusProfileColors._resolveToned(
      colors: colors,
      decoration: decoration,
      artwork: artwork == null
          ? null
          : toneFor(
              artwork,
              dark: colors.background.computeLuminance() < 0.5,
              tone: tone,
            ),
      // Nearly colourless artwork (near-white, grey, blue-grey) tints the
      // page gently, in proportion to its colour: it never invents one.
      quiet: artwork == null ? 1 : quietFactor(artwork, tone),
    );
  }

  factory SonusProfileColors._resolveToned({
    required SonusColors colors,
    required SonusDecorationTokens decoration,
    SonusArtworkColors? artwork,
    double quiet = 1,
  }) {
    final flat = !decoration.allowGradients;
    final target = artwork == null || flat
        ? 0.0
        : strengthFor(decoration.intensity) * quiet;

    final strength = SonusArtworkTint.strongestReadable(
      target,
      (strength) => _readable(colors, artwork!, strength),
    );

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
    final light = tinted ? _light(artwork) : const Color(0x00000000);

    final accent = _accent(colors, decoration, tinted ? artwork : null, [
      background,
      backgroundDeep,
      surface,
      ..._glassGrounds(surface, background, backgroundDeep, light),
    ]);
    final onAccent = accent == colors.accentPrimary
        ? colors.onAccentPrimary
        : SonusArtworkTint.onColour(accent);

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
      light: light,
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

  /// The colour of the page's soft ambient light (SonusProfileBackdrop),
  /// between the artwork's deep tone and its accent; transparent when
  /// untinted.
  final Color light;

  final Color accent;
  final Color onAccent;

  /// The theme's text colours, readable on every ground above.
  final Color textPrimary;
  final Color textSecondary;

  /// How strongly the artwork tints the theme, from 0 (not at all) to 1.
  final double strength;

  bool get isTinted => strength > 0;

  /// These colours over the artwork environment and frosted glass (Profile
  /// Lab method): secondary text takes a lighter tone, halfway to the
  /// primary text, so it keeps 4.5:1 on its local ground. Without effects
  /// the theme's own secondary text stays.
  SonusProfileColors forEnvironment({required bool effects}) {
    if (!effects) return this;
    return SonusProfileColors(
      background: background,
      backgroundDeep: backgroundDeep,
      surface: surface,
      edge: edge,
      glow: glow,
      light: light,
      accent: accent,
      onAccent: onAccent,
      textPrimary: textPrimary,
      textSecondary: Color.lerp(textSecondary, textPrimary, 0.5)!,
      strength: strength,
    );
  }

  bool get hasGlow => glow.a > 0;

  /// The same colours for widgets that take the quieter atmosphere type.
  SonusAtmosphereColors get atmosphere => SonusAtmosphereColors(
    background: background,
    surface: surface,
    accent: accent,
    onAccent: onAccent,
    isTinted: isTinted,
  );

  /// How much of the tint reaches the bottom of the page, and the glass:
  /// most of it, so the page never turns generic charcoal (V1); the
  /// redesign keeps the colour all the way down the scroll.
  static const double deepShare = 0.88;
  static const double surfaceShare = 0.85;

  /// How opaque the soft glass is (SonusSoftGlass), and its top highlight.
  static const double glassAlpha = 0.55;
  static const double glassHighlight = 0.07;

  /// The strongest the ambient light gets anywhere on the page.
  static const double ambientAlpha = 0.30;

  /// Tint strength for each Decoration level: enough for the artwork's
  /// colour to carry the page (profile redesign: raised from 0.30, 0.52
  /// and 0.66, which left cool artwork near charcoal, about half the
  /// saturation of the approved reference). The contrast guard still
  /// weakens it wherever text would suffer.
  static double strengthFor(SonusDecorationIntensity intensity) =>
      switch (intensity) {
        SonusDecorationIntensity.off => 0,
        SonusDecorationIntensity.subtle => 0.45,
        SonusDecorationIntensity.standard => 0.76,
        SonusDecorationIntensity.expressive => 0.86,
      };

  /// 1 for colourful artwork; less for nearly colourless artwork, in
  /// proportion to the cube of its saturation, so near-white and grey
  /// covers stay quiet instead of being lifted into a colour they lack.
  @visibleForTesting
  static double quietFactor(SonusArtworkColors artwork, SonusArtworkTone tone) {
    final saturation = HSLColor.fromColor(artwork.container).saturation;
    if (saturation >= tone.colourfulSaturation) return 1;
    final share = saturation / tone.colourfulSaturation;
    return share * share * share;
  }

  static Color _tint(Color base, SonusArtworkColors artwork, double amount) =>
      SonusArtworkTint.tint(base, artwork, amount);

  /// The artwork's colours as the page uses them (device audit, V2
  /// follow-up). Material's extraction keeps the artwork's own tone, so
  /// bright artwork gives a light "container" (pale blue, orange, yellow).
  /// Tinting a dark page toward a light colour broke text contrast at once,
  /// and the contrast guard then removed the tint entirely: the Madison
  /// Beer, locket, Zara Larsson and Midnight Sun pages came out plain
  /// charcoal. The page now tints toward the artwork's hue at a fixed,
  /// readable luminance (deep for dark themes, pale for light ones), which
  /// treats every hue alike, yellow included. A colourless accent (white
  /// or grey) takes the artwork's hue instead. The contrast guard stays.
  @visibleForTesting
  static SonusArtworkColors toneFor(
    SonusArtworkColors artwork, {
    required bool dark,
    SonusArtworkTone tone = SonusArtworkTone.standard,
  }) {
    // Colourful artwork is lifted to at least [minTintSaturation], so a
    // soft blue cover still gives a clearly blue page; nearly colourless
    // artwork keeps its own (low) saturation.
    // Nearly colourless artwork keeps even less of its faint cast, by the
    // same [quietFactor] that softens its tint, so the page reads neutral.
    final saturation = HSLColor.fromColor(artwork.container).saturation;
    final colourful = saturation >= tone.colourfulSaturation;
    final container = _atLuminance(
      artwork.container,
      dark ? tone.darkTintLuminance : tone.lightTintLuminance,
      minSaturation: colourful ? tone.minTintSaturation : 0,
      maxSaturation: colourful
          ? tone.maxTintSaturation
          : saturation * quietFactor(artwork, tone),
    );
    // A colourless accent (white, grey) takes the artwork's hue, but only
    // when the artwork has one: near-white artwork keeps its own accent.
    final colourless = tone.colourlessAccentSaturation;
    final accent =
        HSLColor.fromColor(artwork.accent).saturation < colourless &&
            HSLColor.fromColor(artwork.container).saturation >= colourless
        ? _atLuminance(
            artwork.container,
            dark ? tone.darkAccentLuminance : tone.lightAccentLuminance,
            minSaturation: tone.minAccentSaturation,
            maxSaturation: tone.maxAccentSaturation,
          )
        : artwork.accent;
    return SonusArtworkColors(accent: accent, container: container);
  }

  /// [colour]'s hue at [luminance], its saturation kept within bounds:
  /// never above [maxSaturation], so neon stays wearable, and only raised
  /// to [minSaturation] where that is asked for (the page tint asks for
  /// none, so near-grey artwork stays quiet).
  static Color _atLuminance(
    Color colour,
    double luminance, {
    required double minSaturation,
    required double maxSaturation,
  }) {
    final hsl = HSLColor.fromColor(colour);
    final base = hsl.withSaturation(
      hsl.saturation.clamp(minSaturation, maxSaturation),
    );
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (base.withLightness(mid).toColor().computeLuminance() < luminance) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return base.withLightness(low).toColor();
  }

  /// The ambient light: between the artwork's deep tone and its accent,
  /// its luminance capped at [maxLightLuminance] so a luminous hue (bright
  /// green, yellow) glows without washing out the text it sits behind.
  static Color _light(SonusArtworkColors artwork) {
    final mixed = Color.lerp(artwork.container, artwork.accent, 0.5)!;
    if (mixed.computeLuminance() <= maxLightLuminance) return mixed;
    return _atLuminance(
      mixed,
      maxLightLuminance,
      minSaturation: 0,
      maxSaturation: 1,
    );
  }

  /// The brightest the ambient light's colour may be.
  static const double maxLightLuminance = 0.16;

  /// What text actually sits on: the soft glass (SonusSoftGlass) over the
  /// page, with and without its highlight, and the page where the ambient
  /// light is strongest.
  static List<Color> _glassGrounds(
    Color surface,
    Color background,
    Color backgroundDeep,
    Color light,
  ) {
    final glass = [
      for (final page in [background, backgroundDeep])
        Color.alphaBlend(surface.withValues(alpha: glassAlpha), page),
    ];
    return [
      ...glass,
      for (final ground in glass)
        Color.alphaBlend(
          const Color(0xFFFFFFFF).withValues(alpha: glassHighlight),
          ground,
        ),
      for (final page in [background, backgroundDeep])
        Color.alphaBlend(light.withValues(alpha: ambientAlpha), page),
    ];
  }

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
      for (final glass in _glassGrounds(
        surface,
        background,
        deep,
        _light(artwork),
      ))
        (colors.background, glass),
    ];
    for (final text in [colors.textPrimary, colors.textSecondary]) {
      for (final (themeGround, tinted) in grounds) {
        if (!SonusArtworkTint.keepsThemeContrast(text, themeGround, tinted)) {
          return false;
        }
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
    return SonusArtworkTint.distinctAccent(
      artwork.accent,
      grounds,
      fallback: colors.accentPrimary,
    );
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
      light: Color.lerp(a.light, b.light, t)!,
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
      other.light == light &&
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
    light,
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

/// How the profile colours carry an artwork's hue (device-audit fix): the
/// luminance the page is tinted toward, and the saturation bounds that keep
/// near-grey artwork quiet and neon wearable. [standard] is today's single
/// setting; Sonus Themes 2.0 can offer others (a theme's personality, or a
/// reactivity mode) without changing the resolver. The contrast guard in
/// [SonusProfileColors.resolve] applies to every tone.
@immutable
class SonusArtworkTone {
  const SonusArtworkTone({
    required this.darkTintLuminance,
    required this.lightTintLuminance,
    required this.minTintSaturation,
    required this.maxTintSaturation,
    required this.darkAccentLuminance,
    required this.lightAccentLuminance,
    required this.minAccentSaturation,
    required this.maxAccentSaturation,
    required this.colourlessAccentSaturation,
    this.colourfulSaturation = 0.25,
  });

  /// The profile redesign's tone: a deep page carrying the artwork's hue at
  /// a saturation near the approved reference (about 45% for a soft blue
  /// cover), never above 90%.
  static const SonusArtworkTone standard = SonusArtworkTone(
    darkTintLuminance: 0.055,
    lightTintLuminance: 0.75,
    minTintSaturation: 0.50,
    maxTintSaturation: 0.90,
    darkAccentLuminance: 0.45,
    lightAccentLuminance: 0.12,
    minAccentSaturation: 0.50,
    maxAccentSaturation: 0.90,
    colourlessAccentSaturation: 0.20,
  );

  /// Luminance the page is tinted toward, on dark and on light themes.
  final double darkTintLuminance;
  final double lightTintLuminance;

  /// Saturation bounds of the tint. The minimum applies to colourful
  /// artwork only, so near-grey artwork is never made colourful.
  final double minTintSaturation;
  final double maxTintSaturation;

  /// Luminance and saturation bounds of an accent made from the artwork's
  /// hue, when its own accent is colourless.
  final double darkAccentLuminance;
  final double lightAccentLuminance;
  final double minAccentSaturation;
  final double maxAccentSaturation;

  /// Below this saturation an extracted accent counts as colourless.
  final double colourlessAccentSaturation;

  /// From this saturation an artwork counts as colourful: it gets the full
  /// tint and the [minTintSaturation] floor. Below it the page stays quiet
  /// (see [SonusProfileColors.quietFactor]).
  final double colourfulSaturation;
}
