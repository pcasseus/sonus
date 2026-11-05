/// How much a theme lets artwork colour Sonus (Sonus Themes 2.0, T1).
///
/// - [static]: the theme's own colours.
/// - [ambient]: artwork nudges the theme, as the player and mini-player
///   do today, and artwork-adaptive pages (Artist and Album Profiles) keep
///   their own atmosphere.
/// - [immersive]: room for stronger, profile-class artwork colour.
///
/// Each theme has a default ([SonusThemeDefinition.reactivityDefault]); the
/// user may choose another. The effective mode is clamped by accessibility:
/// High contrast, Low effects and Decoration Off make it [static]
/// (see `SonusDecorationTokens.reactivity`).
///
/// T1 adds the vocabulary, defaults, clamping and the saved preference
/// only. Which surfaces react in each mode (now-playing colour on the
/// mini-player and navigation, the Immersive backdrop) is later work that
/// needs its own approval and device performance checks.
enum SonusReactivityMode {
  static('static', 'Static'),
  ambient('ambient', 'Ambient'),
  immersive('immersive', 'Immersive');

  const SonusReactivityMode(this.storageKey, this.label);

  /// Stable key for saved preferences.
  final String storageKey;

  /// Shown in Appearance Settings.
  final String label;

  static SonusReactivityMode? fromStorageKey(Object? key) {
    for (final mode in values) {
      if (mode.storageKey == key) return mode;
    }
    return null;
  }

  /// [requested], or [static] when the accessibility and decoration
  /// settings do not allow artwork colour at all.
  static SonusReactivityMode clamp(
    SonusReactivityMode requested, {
    required bool allowGradients,
  }) => allowGradients ? requested : static;
}

/// How a theme draws raised surfaces (Themes 2.0 T1 token; every theme is
/// [glass] today, so nothing changes until a theme opts into [flat]).
enum SonusSurfaceStyle { glass, flat }
