import 'package:flutter/foundation.dart';

import '../../../../core/design/sonus_reactivity.dart';
import '../../../../core/design/sonus_theme_catalog.dart';
import '../../../../core/design/sonus_theme_id.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../domain/models/appearance_preferences.dart';
import '../controllers/appearance_controller.dart';

/// One on/off appearance setting and where its effective value comes from.
@immutable
class AppearanceSwitchState {
  const AppearanceSwitchState({
    required this.chosen,
    this.fromDevice = false,
    this.deviceSettingName,
  });

  /// The switch in Sonus.
  final bool chosen;

  /// The device's own accessibility setting asks for it.
  final bool fromDevice;

  /// The device setting's name, e.g. "Remove animations".
  final String? deviceSettingName;

  bool get effective => chosen || fromDevice;

  String get label {
    if (!effective) return 'Off';
    if (!fromDevice) return 'On';
    final source = deviceSettingName == null
        ? 'your device asks for it'
        : "from your device's $deviceSettingName setting";
    return chosen ? 'On (also $source)' : 'On ($source)';
  }
}

/// Why artwork backgrounds, glows or glass are reduced.
enum AppearanceAtmosphereLimit {
  lowEffects(
    'Low effects',
    'Low effects is on: artwork backgrounds, glows and glass are off on '
        'this device.',
  ),
  decorationOff(
    'Decoration Off',
    'Decoration is Off: artwork backgrounds, glows and glass are off.',
  ),
  highContrast(
    'High contrast',
    'High contrast is on: profiles keep a restrained artwork backdrop '
        'behind solid, high-contrast panels; glows and glass are off.',
  ),
  decorationSubtle(
    'Subtle decoration',
    'Decoration is Subtle: artwork colours stay on, but glows are off.',
  );

  const AppearanceAtmosphereLimit(this.title, this.explanation);

  final String title;
  final String explanation;
}

/// A read-only account of the effective appearance, for troubleshooting
/// why a screen looks the way it does.
@immutable
class AppearanceSummary {
  const AppearanceSummary({
    required this.theme,
    required this.chosenDecoration,
    required this.effectiveDecoration,
    required this.highContrast,
    required this.boldText,
    required this.lowEffects,
    required this.reduceMotion,
    required this.requestedReactivity,
    required this.reactivityIsThemeDefault,
    required this.effectiveReactivity,
    required this.limits,
  });

  /// Combines the stored choices, the device's accessibility signals and
  /// the effective decoration tokens of the active theme.
  factory AppearanceSummary.resolve({
    required SonusThemeId theme,
    required AppearancePreferences preferences,
    required AppearanceDeviceSettings device,
    required bool systemHighContrast,
    required bool systemReduceMotion,
    bool systemBoldText = false,
    required SonusDecorationTokens decoration,
  }) {
    final highContrast = AppearanceSwitchState(
      chosen: preferences.highContrast,
      fromDevice: systemHighContrast,
    );
    final boldText = AppearanceSwitchState(
      chosen: preferences.boldText,
      fromDevice: systemBoldText,
      deviceSettingName: 'Bold text',
    );
    final lowEffects = AppearanceSwitchState(chosen: device.lowEffects);
    final reduceMotion = AppearanceSwitchState(
      chosen: preferences.reduceMotion,
      fromDevice: systemReduceMotion,
      deviceSettingName: 'Remove animations',
    );

    final limits = <AppearanceAtmosphereLimit>[
      if (lowEffects.effective || decoration.lowEffects)
        AppearanceAtmosphereLimit.lowEffects,
      if (preferences.decoration == SonusDecorationIntensity.off)
        AppearanceAtmosphereLimit.decorationOff,
      if (highContrast.effective || decoration.highContrast)
        AppearanceAtmosphereLimit.highContrast,
      if (preferences.decoration == SonusDecorationIntensity.subtle)
        AppearanceAtmosphereLimit.decorationSubtle,
    ];

    return AppearanceSummary(
      theme: theme,
      chosenDecoration: preferences.decoration,
      effectiveDecoration: decoration.intensity,
      highContrast: highContrast,
      boldText: boldText,
      lowEffects: lowEffects,
      reduceMotion: reduceMotion,
      requestedReactivity:
          preferences.reactivity ??
          SonusThemeCatalog.of(theme).reactivityDefault,
      reactivityIsThemeDefault: preferences.reactivity == null,
      effectiveReactivity: decoration.reactivity,
      limits: List.unmodifiable(limits),
    );
  }

  /// [AppearanceSummary.resolve] for [controller]'s current state.
  factory AppearanceSummary.of(
    AppearanceController controller,
    SonusDecorationTokens decoration,
  ) {
    return AppearanceSummary.resolve(
      theme: controller.resolved.theme,
      preferences: controller.preferences,
      device: controller.device,
      systemHighContrast: controller.systemHighContrast,
      systemReduceMotion: controller.systemReduceMotion,
      systemBoldText: controller.systemBoldText,
      decoration: decoration,
    );
  }

  static const String unlimitedExplanation =
      'Nothing is limiting artwork atmospheres: artwork backgrounds, glows '
      'and glass are on.';

  final SonusThemeId theme;
  final SonusDecorationIntensity chosenDecoration;
  final SonusDecorationIntensity effectiveDecoration;
  final AppearanceSwitchState highContrast;

  /// Typography only; never limits artwork atmospheres.
  final AppearanceSwitchState boldText;
  final AppearanceSwitchState lowEffects;
  final AppearanceSwitchState reduceMotion;
  final SonusReactivityMode requestedReactivity;
  final bool reactivityIsThemeDefault;
  final SonusReactivityMode effectiveReactivity;

  /// Every active cause, most restrictive first. Empty when nothing limits
  /// artwork atmospheres.
  final List<AppearanceAtmosphereLimit> limits;

  String get themeLabel => theme.label;

  String get decorationLabel => chosenDecoration == effectiveDecoration
      ? chosenDecoration.label
      : '${chosenDecoration.label} (limited to ${effectiveDecoration.label})';

  String get reactivityLabel {
    final requested = reactivityIsThemeDefault
        ? '${requestedReactivity.label} (theme default)'
        : requestedReactivity.label;
    if (effectiveReactivity == requestedReactivity) return requested;
    return '${effectiveReactivity.label} (chosen: $requested; limited by '
        'the settings below)';
  }

  /// The plain-language reasons, or [unlimitedExplanation].
  List<String> get explanations => limits.isEmpty
      ? const [unlimitedExplanation]
      : [for (final limit in limits) limit.explanation];
}
