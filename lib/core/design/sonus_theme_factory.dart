import 'package:flutter/material.dart';

import 'sonus_contrast.dart';
import 'sonus_theme_catalog.dart';
import 'sonus_theme_definition.dart';
import 'sonus_theme_id.dart';
import 'sonus_tokens.dart';
import 'sonus_typography.dart';

/// The fully resolved inputs of one rendered theme.
///
/// [highContrast] and [reduceMotion] are effective values: the user's
/// in-app choices already combined with the device's accessibility signals.
@immutable
class SonusAppearanceSpec {
  const SonusAppearanceSpec({
    this.themeId = SonusThemeId.defaultTheme,
    this.typography = SonusTypographyPreset.defaultPreset,
    this.decoration = SonusDecorationIntensity.standard,
    this.highContrast = false,
    this.reduceMotion = false,
    this.lowEffects = false,
  });

  final SonusThemeId themeId;
  final SonusTypographyPreset typography;
  final SonusDecorationIntensity decoration;
  final bool highContrast;
  final bool reduceMotion;
  final bool lowEffects;

  SonusAppearanceSpec copyWith({SonusThemeId? themeId}) {
    return SonusAppearanceSpec(
      themeId: themeId ?? this.themeId,
      typography: typography,
      decoration: decoration,
      highContrast: highContrast,
      reduceMotion: reduceMotion,
      lowEffects: lowEffects,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SonusAppearanceSpec &&
        other.themeId == themeId &&
        other.typography == typography &&
        other.decoration == decoration &&
        other.highContrast == highContrast &&
        other.reduceMotion == reduceMotion &&
        other.lowEffects == lowEffects;
  }

  @override
  int get hashCode => Object.hash(
    themeId,
    typography,
    decoration,
    highContrast,
    reduceMotion,
    lowEffects,
  );
}

/// Builds Material [ThemeData] plus Sonus extensions from a spec.
///
/// This is the only place theme definitions are interpreted, so screens
/// never branch on theme names.
abstract final class SonusThemeFactory {
  // The input domain is finite (a few hundred specs), so the cache is
  // naturally bounded.
  static final Map<SonusAppearanceSpec, ThemeData> _cache = {};

  static ThemeData build(SonusAppearanceSpec spec) {
    return _cache.putIfAbsent(spec, () => _build(spec));
  }

  static ThemeData _build(SonusAppearanceSpec spec) {
    final definition = SonusThemeCatalog.of(spec.themeId);
    final colors = colorsFor(definition, highContrast: spec.highContrast);
    final scheme = _colorScheme(definition.palette, colors);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: definition.palette.brightness,
    );

    final textTheme = SonusTypography.apply(
      base.textTheme,
      spec.typography,
      colors.textPrimary,
    );

    final metrics = SonusMetrics(
      cardRadius: definition.cardRadius,
      artworkRadius: definition.artworkRadius,
    );

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(definition.cardRadius),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      dividerColor: colors.divider,
      focusColor: colors.focus.withValues(alpha: 0.24),
      splashFactory: spec.reduceMotion || spec.lowEffects
          ? InkRipple.splashFactory
          : base.splashFactory,
      pageTransitionsTheme: spec.reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _InstantPageTransitionsBuilder(),
                TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
                TargetPlatform.windows: _InstantPageTransitionsBuilder(),
                TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
                TargetPlatform.linux: _InstantPageTransitionsBuilder(),
                TargetPlatform.fuchsia: _InstantPageTransitionsBuilder(),
              },
            )
          : base.pageTransitionsTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textSecondary,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: colors.accentPrimary,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colors.accentPrimary, width: 3),
          borderRadius: BorderRadius.circular(2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: colors.divider,
        tabAlignment: TabAlignment.start,
        // Keyboard focus gets a stronger wash than touch feedback so the
        // focused destination stays visible in every theme.
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? colors.focus.withValues(alpha: 0.24)
              : colors.selection,
        ),
        splashBorderRadius: BorderRadius.circular(metrics.controlRadius),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.raisedSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: colors.divider),
      listTileTheme: ListTileThemeData(iconColor: colors.textSecondary),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.progressActive,
        linearTrackColor: colors.progressInactive,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.progressActive,
        inactiveTrackColor: colors.progressInactive,
        thumbColor: colors.progressActive,
      ),
      extensions: [
        colors,
        SonusTextStyles.fromTextTheme(textTheme),
        metrics,
        decorationFor(definition, spec),
        SonusMotion(reduced: spec.reduceMotion, curve: definition.motionCurve),
      ],
    );
  }

  /// Semantic colours of [definition], optionally in high contrast.
  static SonusColors colorsFor(
    SonusThemeDefinition definition, {
    required bool highContrast,
  }) {
    final palette = definition.palette;

    final textSecondary = highContrast
        ? Color.lerp(palette.secondaryText, palette.text, 0.6)!
        : palette.secondaryText;

    final onPrimary = _onAccent(palette.primary, palette);
    final onSecondary = _onAccent(palette.secondary, palette);
    final placeholder = Color.lerp(
      palette.raisedSurface,
      palette.neutral,
      0.3,
    )!;

    return SonusColors(
      background: palette.background,
      surface: palette.surface,
      raisedSurface: palette.raisedSurface,
      textPrimary: palette.text,
      textSecondary: textSecondary,
      border: highContrast ? textSecondary : _border(palette),
      divider: highContrast
          ? Color.lerp(palette.divider, palette.secondaryText, 0.5)!
          : palette.divider,
      accentPrimary: palette.primary,
      onAccentPrimary: onPrimary,
      accentSecondary: palette.secondary,
      onAccentSecondary: onSecondary,
      selection: palette.primary.withValues(alpha: 0.18),
      focus: highContrast ? palette.text : palette.primary,
      chartUp: palette.chartUp,
      chartDown: palette.chartDown,
      chartNew: palette.secondary,
      chartSteady: textSecondary,
      storyFeatured: palette.raisedSurface,
      onStoryFeatured: palette.text,
      artworkPlaceholder: placeholder,
      onArtworkPlaceholder: textSecondary,
      artworkFrame: highContrast ? textSecondary : palette.divider,
      artworkScrim: Colors.black.withValues(alpha: highContrast ? 0.82 : 0.6),
      onArtworkScrim: Colors.white,
      playbackControl: palette.primary,
      onPlaybackControl: onPrimary,
      progressActive: palette.primary,
      progressInactive: Color.lerp(
        palette.raisedSurface,
        palette.neutral,
        0.6,
      )!,
      decorationPrimary: palette.secondary,
      decorationSecondary: palette.primary,
    );
  }

  /// Decoration after the low-effects and high-contrast limits.
  static SonusDecorationTokens decorationFor(
    SonusThemeDefinition definition,
    SonusAppearanceSpec spec,
  ) {
    var intensity = spec.decoration;
    final limited = spec.lowEffects || spec.highContrast;

    if (limited && intensity.index > SonusDecorationIntensity.subtle.index) {
      intensity = SonusDecorationIntensity.subtle;
    }

    final atLeastStandard =
        intensity.index >= SonusDecorationIntensity.standard.index;

    return SonusDecorationTokens(
      intensity: intensity,
      motif: definition.motif,
      markOpacity: switch (intensity) {
        SonusDecorationIntensity.off => 0,
        SonusDecorationIntensity.subtle => spec.highContrast ? 1 : 0.5,
        SonusDecorationIntensity.standard => 0.85,
        SonusDecorationIntensity.expressive => 1,
      },
      showTexture: definition.hasTexture && atLeastStandard && !limited,
      textureOpacity: intensity == SonusDecorationIntensity.expressive
          ? 0.06
          : 0.035,
      allowGlow: atLeastStandard && !limited,
      allowGradients: intensity != SonusDecorationIntensity.off && !limited,
      progressStyle: definition.progressStyle,
    );
  }

  static ColorScheme _colorScheme(SonusPalette palette, SonusColors colors) {
    final dark = palette.brightness == Brightness.dark;

    Color container(Color accent) =>
        Color.lerp(accent, palette.raisedSurface, 0.78)!;

    return ColorScheme(
      brightness: palette.brightness,
      primary: palette.primary,
      onPrimary: colors.onAccentPrimary,
      primaryContainer: container(palette.primary),
      onPrimaryContainer: palette.text,
      secondary: palette.secondary,
      onSecondary: colors.onAccentSecondary,
      secondaryContainer: container(palette.secondary),
      onSecondaryContainer: palette.text,
      tertiary: palette.tertiary,
      onTertiary: _onAccent(palette.tertiary, palette),
      tertiaryContainer: container(palette.tertiary),
      onTertiaryContainer: palette.text,
      error: palette.error,
      onError: _onAccent(palette.error, palette),
      errorContainer: container(palette.error),
      onErrorContainer: palette.text,
      surface: palette.background,
      onSurface: palette.text,
      surfaceDim: Color.lerp(
        palette.background,
        dark ? Colors.black : palette.neutral,
        0.2,
      ),
      surfaceBright: palette.raisedSurface,
      surfaceContainerLowest: dark
          ? Color.lerp(palette.background, Colors.black, 0.25)
          : palette.surface,
      surfaceContainerLow: Color.lerp(palette.background, palette.surface, 0.5),
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.raisedSurface,
      surfaceContainerHighest: colors.artworkPlaceholder,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.text,
      onInverseSurface: palette.background,
      inversePrimary: Color.lerp(palette.primary, palette.background, 0.4),
      surfaceTint: Colors.transparent,
    );
  }

  /// The palette extreme with the better contrast on [accent].
  static Color _onAccent(Color accent, SonusPalette palette) {
    final darkText = palette.brightness == Brightness.dark
        ? palette.background
        : palette.text;
    final lightText = palette.brightness == Brightness.dark
        ? palette.text
        : palette.surface;

    return SonusContrast.ratio(accent, darkText) >=
            SonusContrast.ratio(accent, lightText)
        ? darkText
        : lightText;
  }

  /// The closest colour to the theme's neutral that still reaches 3:1
  /// against every surface, as WCAG requires for control borders.
  static Color _border(SonusPalette palette) {
    for (var step = 0; step <= 10; step++) {
      final candidate = Color.lerp(
        palette.neutral,
        palette.secondaryText,
        step / 10,
      )!;

      final surfaces = [
        palette.background,
        palette.surface,
        palette.raisedSurface,
      ];

      if (surfaces.every((s) => SonusContrast.ratio(candidate, s) >= 3)) {
        return candidate;
      }
    }

    return palette.secondaryText;
  }
}

/// Shows the next route immediately, for reduced motion.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
