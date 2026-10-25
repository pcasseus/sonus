import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart';

import 'sonus_artwork_palette.dart';

/// The colours a profile page paints with: theme colours, nudged by the
/// artwork (SN-48J J6, shared with the Artist Profile in SN-48I).
@immutable
class SonusAtmosphereColors {
  const SonusAtmosphereColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.isTinted,
  });

  factory SonusAtmosphereColors.of(SonusArtworkAtmosphere atmosphere) {
    return SonusAtmosphereColors(
      background: atmosphere.background,
      surface: atmosphere.surface,
      accent: atmosphere.accent,
      onAccent: atmosphere.onAccent,
      isTinted: atmosphere.isTinted,
    );
  }

  final Color background;
  final Color surface;
  final Color accent;
  final Color onAccent;
  final bool isTinted;

  static SonusAtmosphereColors lerp(
    SonusAtmosphereColors a,
    SonusAtmosphereColors b,
    double t,
  ) {
    return SonusAtmosphereColors(
      background: Color.lerp(a.background, b.background, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      // The text colour on the accent switches rather than blends, so it
      // never passes through a low-contrast midpoint.
      onAccent: t < 0.5 ? a.onAccent : b.onAccent,
      isTinted: t < 0.5 ? a.isTinted : b.isTinted,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SonusAtmosphereColors &&
      other.background == background &&
      other.surface == surface &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.isTinted == isTinted;

  @override
  int get hashCode =>
      Object.hash(background, surface, accent, onAccent, isTinted);
}

class SonusAtmosphereColorsTween extends Tween<SonusAtmosphereColors> {
  SonusAtmosphereColorsTween({super.end});

  @override
  SonusAtmosphereColors lerp(double t) =>
      SonusAtmosphereColors.lerp(begin!, end!, t);
}
