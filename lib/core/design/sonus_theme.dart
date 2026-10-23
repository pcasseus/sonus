import 'package:flutter/material.dart';

import 'sonus_tokens.dart';

/// Every Sonus token for one [BuildContext].
@immutable
class SonusThemeData {
  const SonusThemeData({
    required this.colors,
    required this.text,
    required this.metrics,
    required this.decoration,
    required this.motion,
  });

  final SonusColors colors;
  final SonusTextStyles text;
  final SonusMetrics metrics;
  final SonusDecorationTokens decoration;
  final SonusMotion motion;
}

/// Reads Sonus tokens from the ambient [Theme].
///
/// Widgets rendered without a Sonus theme (for example tests that build
/// their own [MaterialApp]) receive tokens derived from the ambient
/// [ColorScheme] and [TextTheme], with decoration switched off, so they
/// never fail on a missing extension.
abstract final class SonusTheme {
  static SonusThemeData of(BuildContext context) {
    final theme = Theme.of(context);

    // The device can ask for reduced motion after the theme was built.
    final systemReducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final motion =
        theme.extension<SonusMotion>() ??
        const SonusMotion(reduced: false, curve: Curves.easeOutCubic);

    return SonusThemeData(
      colors:
          theme.extension<SonusColors>() ??
          SonusColors.fromColorScheme(theme.colorScheme),
      text:
          theme.extension<SonusTextStyles>() ??
          SonusTextStyles.fromTextTheme(theme.textTheme),
      metrics: theme.extension<SonusMetrics>() ?? const SonusMetrics(),
      decoration:
          theme.extension<SonusDecorationTokens>() ??
          const SonusDecorationTokens.none(),
      motion: systemReducedMotion ? motion.copyWith(reduced: true) : motion,
    );
  }
}
