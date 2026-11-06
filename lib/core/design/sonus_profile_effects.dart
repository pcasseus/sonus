import 'sonus_tokens.dart';

/// How much of the artwork environment a profile page draws.
enum SonusProfileBackdrop {
  /// The full environment: tone-mapped artwork, light, frosted glass.
  full,

  /// High contrast: a restrained, darker artwork backdrop behind solid,
  /// high-contrast panels and text grounds. No glow, glass or light pools.
  restrained,

  /// No artwork behind the content: Low effects or Decoration Off.
  none,
}

/// The profile backdrop the current appearance allows. High contrast keeps
/// a restrained artwork identity (legibility comes from solid panels and
/// strong text, not from removing the artwork); Low effects and Decoration
/// Off remove it.
SonusProfileBackdrop sonusProfileBackdrop(SonusDecorationTokens decoration) {
  if (decoration.allowGradients) return SonusProfileBackdrop.full;
  if (decoration.highContrast &&
      !decoration.lowEffects &&
      decoration.intensity != SonusDecorationIntensity.off) {
    return SonusProfileBackdrop.restrained;
  }
  return SonusProfileBackdrop.none;
}
