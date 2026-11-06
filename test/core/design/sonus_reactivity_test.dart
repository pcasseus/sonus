// Sonus Themes 2.0, T1: theme tokens for artwork reactivity, control radius
// and surface style. Vocabulary, per-theme defaults and accessibility
// clamping only; nothing on screen changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_reactivity.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';

SonusDecorationTokens tokens(SonusAppearanceSpec spec) =>
    SonusThemeFactory.build(spec).extension<SonusDecorationTokens>()!;

void main() {
  test('every theme keeps today\'s behaviour: Ambient, 12 radius, glass', () {
    for (final id in SonusThemeId.values) {
      final definition = SonusThemeCatalog.of(id);
      expect(definition.reactivityDefault, SonusReactivityMode.ambient);
      expect(definition.controlRadius, 12);
      expect(definition.surfaceStyle, SonusSurfaceStyle.glass);

      final theme = SonusThemeFactory.build(SonusAppearanceSpec(themeId: id));
      expect(theme.extension<SonusMetrics>()!.controlRadius, 12);
      expect(
        tokens(SonusAppearanceSpec(themeId: id)).reactivity,
        SonusReactivityMode.ambient,
      );
    }
  });

  test('the user\'s choice overrides the theme default', () {
    for (final mode in SonusReactivityMode.values) {
      expect(tokens(SonusAppearanceSpec(reactivity: mode)).reactivity, mode);
    }
  });

  test('accessibility and Decoration Off make every mode Static', () {
    for (final mode in SonusReactivityMode.values) {
      for (final spec in [
        SonusAppearanceSpec(reactivity: mode, highContrast: true),
        SonusAppearanceSpec(reactivity: mode, lowEffects: true),
        SonusAppearanceSpec(
          reactivity: mode,
          decoration: SonusDecorationIntensity.off,
        ),
      ]) {
        expect(tokens(spec).reactivity, SonusReactivityMode.static);
      }
    }
    // Subtle decoration still allows artwork colour.
    expect(
      tokens(
        const SonusAppearanceSpec(
          reactivity: SonusReactivityMode.immersive,
          decoration: SonusDecorationIntensity.subtle,
        ),
      ).reactivity,
      SonusReactivityMode.immersive,
    );
  });

  test('the spec compares and copies its reactivity', () {
    const a = SonusAppearanceSpec(reactivity: SonusReactivityMode.immersive);
    const b = SonusAppearanceSpec(reactivity: SonusReactivityMode.immersive);
    const c = SonusAppearanceSpec();
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(
      a.copyWith(themeId: SonusThemeId.evergreen).reactivity,
      SonusReactivityMode.immersive,
    );
  });

  test('storage keys are stable and round-trip', () {
    expect(SonusReactivityMode.values.map((mode) => mode.storageKey), [
      'static',
      'ambient',
      'immersive',
    ]);
    for (final mode in SonusReactivityMode.values) {
      expect(SonusReactivityMode.fromStorageKey(mode.storageKey), mode);
    }
    expect(SonusReactivityMode.fromStorageKey('vivid'), isNull);
    expect(SonusReactivityMode.fromStorageKey(null), isNull);
  });
}
