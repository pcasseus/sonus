import 'package:flutter/painting.dart';

import '../sonus_artwork_palette.dart';
import '../sonus_contrast.dart';

/// The one engine every artwork-tint resolver uses (theme architecture T0):
/// how a ground is tinted toward the artwork, how far a tint is weakened to
/// keep text readable, when the artwork's accent may replace the theme's,
/// and which text colour sits on an accent.
///
/// Resolvers differ only in their parameters (strength per Decoration
/// level, which grounds are checked, the base colours): Profile tints the
/// theme strongly, Atmosphere nudges it, Cinematic replaces it with its own
/// dark base. The arithmetic lives here once, so the three cannot drift.
abstract final class SonusArtworkTint {
  /// How much the tint weakens per step while text is not yet readable.
  static const double weakenStep = 0.02;

  /// [base] moved toward the artwork's container colour by [amount].
  static Color tint(Color base, SonusArtworkColors artwork, double amount) =>
      Color.lerp(base, artwork.container, amount)!;

  /// The strongest tint, from [target] down in [weakenStep]s, for which
  /// [readable] holds; 0 when none does.
  static double strongestReadable(
    double target,
    bool Function(double strength) readable,
  ) {
    var strength = target;
    while (strength > 0 && !readable(strength)) {
      strength = (strength - weakenStep).clamp(0.0, 1.0);
    }
    return strength;
  }

  /// Whether [text] on the [tinted] ground stays as readable as the theme
  /// asks: at least 4.5:1, or never less than [themeGround] itself offers.
  static bool keepsThemeContrast(Color text, Color themeGround, Color tinted) {
    final required = SonusContrast.ratio(text, themeGround).clamp(1.0, 4.5);
    return SonusContrast.ratio(text, tinted) >= required;
  }

  /// [candidate] when it keeps at least [minimum]:1 against every ground,
  /// else [fallback].
  static Color distinctAccent(
    Color candidate,
    Iterable<Color> grounds, {
    required Color fallback,
    double minimum = 3,
  }) {
    final distinct = grounds.every(
      (ground) => SonusContrast.ratio(candidate, ground) >= minimum,
    );
    return distinct ? candidate : fallback;
  }

  /// Black or white, whichever reads better on [colour] (always ≥ 4.5:1).
  static Color onColour(Color colour) {
    const dark = Color(0xFF000000);
    const light = Color(0xFFFFFFFF);
    return SonusContrast.ratio(dark, colour) >=
            SonusContrast.ratio(light, colour)
        ? dark
        : light;
  }
}
