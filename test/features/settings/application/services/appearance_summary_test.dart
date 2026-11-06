import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_reactivity.dart';
import 'package:sonus_next/core/design/sonus_theme_catalog.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/settings/application/services/appearance_summary.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

AppearanceSummary _summary({
  SonusThemeId theme = SonusThemeId.concreteSpray,
  AppearancePreferences preferences = const AppearancePreferences(),
  AppearanceDeviceSettings device = const AppearanceDeviceSettings(),
  bool systemHighContrast = false,
  bool systemReduceMotion = false,
}) {
  final spec = SonusAppearanceSpec(
    themeId: theme,
    typography: preferences.typography,
    decoration: preferences.decoration,
    highContrast: preferences.highContrast || systemHighContrast,
    reduceMotion: preferences.reduceMotion || systemReduceMotion,
    lowEffects: device.lowEffects,
    reactivity: preferences.reactivity,
  );

  return AppearanceSummary.resolve(
    theme: theme,
    preferences: preferences,
    device: device,
    systemHighContrast: systemHighContrast,
    systemReduceMotion: systemReduceMotion,
    decoration: SonusThemeFactory.decorationFor(
      SonusThemeCatalog.of(theme),
      spec,
    ),
  );
}

void main() {
  test('defaults: nothing limits artwork atmospheres', () {
    final summary = _summary();

    expect(summary.limits, isEmpty);
    expect(summary.explanations, [AppearanceSummary.unlimitedExplanation]);
    expect(summary.themeLabel, SonusThemeId.concreteSpray.label);
    expect(summary.decorationLabel, 'Standard');
    expect(summary.highContrast.label, 'Off');
    expect(summary.lowEffects.label, 'Off');
    expect(summary.reduceMotion.label, 'Off');
    expect(summary.reactivityLabel, 'Ambient (theme default)');
  });

  test('Low effects names itself and clamps decoration and reactivity', () {
    final summary = _summary(
      device: const AppearanceDeviceSettings(lowEffects: true),
    );

    expect(summary.limits, [AppearanceAtmosphereLimit.lowEffects]);
    expect(
      summary.explanations.single,
      'Low effects is on: artwork backgrounds, glows and glass are off on '
      'this device.',
    );
    expect(summary.lowEffects.label, 'On');
    expect(summary.decorationLabel, 'Standard (limited to Subtle)');
    expect(summary.effectiveReactivity, SonusReactivityMode.static);
    expect(summary.reactivityLabel, startsWith('Static (chosen: Ambient'));
  });

  test('Decoration Off names itself', () {
    final summary = _summary(
      preferences: const AppearancePreferences(
        decoration: SonusDecorationIntensity.off,
      ),
    );

    expect(summary.limits, [AppearanceAtmosphereLimit.decorationOff]);
    expect(
      summary.explanations.single,
      'Decoration is Off: artwork backgrounds, glows and glass are off.',
    );
    expect(summary.decorationLabel, 'Off');
  });

  test('High contrast keeps a restrained profile backdrop', () {
    final summary = _summary(
      preferences: const AppearancePreferences(highContrast: true),
    );

    expect(summary.limits, [AppearanceAtmosphereLimit.highContrast]);
    expect(
      summary.explanations.single,
      'High contrast is on: profiles keep a restrained artwork backdrop '
      'behind solid, high-contrast panels; glows and glass are off.',
    );
    expect(summary.highContrast.label, 'On');
  });

  test("the device's high contrast is reported as the source", () {
    final summary = _summary(systemHighContrast: true);

    expect(summary.limits, [AppearanceAtmosphereLimit.highContrast]);
    expect(summary.highContrast.label, 'On (your device asks for it)');
  });

  test('Subtle decoration explains that glows are off', () {
    final summary = _summary(
      preferences: const AppearancePreferences(
        decoration: SonusDecorationIntensity.subtle,
      ),
    );

    expect(summary.limits, [AppearanceAtmosphereLimit.decorationSubtle]);
    expect(
      summary.explanations.single,
      'Decoration is Subtle: artwork colours stay on, but glows are off.',
    );
  });

  test('every active cause is listed, most restrictive first', () {
    final summary = _summary(
      preferences: const AppearancePreferences(
        decoration: SonusDecorationIntensity.off,
        highContrast: true,
      ),
      device: const AppearanceDeviceSettings(lowEffects: true),
    );

    expect(summary.limits, [
      AppearanceAtmosphereLimit.lowEffects,
      AppearanceAtmosphereLimit.decorationOff,
      AppearanceAtmosphereLimit.highContrast,
    ]);
  });

  test("reduce motion from Android's Remove animations is named", () {
    expect(
      _summary(systemReduceMotion: true).reduceMotion.label,
      "On (from your device's Remove animations setting)",
    );
    expect(
      _summary(
        preferences: const AppearancePreferences(reduceMotion: true),
        systemReduceMotion: true,
      ).reduceMotion.label,
      "On (also from your device's Remove animations setting)",
    );
    expect(
      _summary(
        preferences: const AppearancePreferences(reduceMotion: true),
      ).reduceMotion.label,
      'On',
    );
  });

  test('a chosen reactivity is shown without the default note', () {
    final summary = _summary(
      preferences: const AppearancePreferences(
        reactivity: SonusReactivityMode.immersive,
      ),
    );

    expect(summary.reactivityLabel, 'Immersive');
  });
}
