import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'sonus_theme_definition.dart';

/// Semantic colours. Screens use roles ("chart up", "artwork scrim"), never
/// theme names, so every theme renders through the same widgets.
@immutable
class SonusColors extends ThemeExtension<SonusColors> {
  const SonusColors({
    required this.background,
    required this.surface,
    required this.raisedSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.accentPrimary,
    required this.onAccentPrimary,
    required this.accentSecondary,
    required this.onAccentSecondary,
    required this.selection,
    required this.focus,
    required this.chartUp,
    required this.chartDown,
    required this.chartNew,
    required this.chartSteady,
    required this.storyFeatured,
    required this.onStoryFeatured,
    required this.artworkPlaceholder,
    required this.onArtworkPlaceholder,
    required this.artworkFrame,
    required this.artworkScrim,
    required this.onArtworkScrim,
    required this.playbackControl,
    required this.onPlaybackControl,
    required this.progressActive,
    required this.progressInactive,
    required this.decorationPrimary,
    required this.decorationSecondary,
  });

  /// Tokens for widgets rendered without a Sonus theme, such as tests that
  /// build their own [MaterialApp]. Derived from the ambient [scheme] so
  /// they stay consistent with it.
  factory SonusColors.fromColorScheme(ColorScheme scheme) {
    return SonusColors(
      background: scheme.surface,
      surface: scheme.surfaceContainer,
      raisedSurface: scheme.surfaceContainerHigh,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      border: scheme.outline,
      divider: scheme.outlineVariant,
      accentPrimary: scheme.primary,
      onAccentPrimary: scheme.onPrimary,
      accentSecondary: scheme.secondary,
      onAccentSecondary: scheme.onSecondary,
      selection: scheme.primary.withValues(alpha: 0.16),
      focus: scheme.primary,
      chartUp: scheme.tertiary,
      chartDown: scheme.error,
      chartNew: scheme.secondary,
      chartSteady: scheme.onSurfaceVariant,
      storyFeatured: scheme.secondaryContainer,
      onStoryFeatured: scheme.onSecondaryContainer,
      artworkPlaceholder: scheme.surfaceContainerHighest,
      onArtworkPlaceholder: scheme.onSurfaceVariant,
      artworkFrame: scheme.outlineVariant,
      artworkScrim: scheme.scrim.withValues(alpha: 0.6),
      onArtworkScrim: Colors.white,
      playbackControl: scheme.primary,
      onPlaybackControl: scheme.onPrimary,
      progressActive: scheme.primary,
      progressInactive: scheme.surfaceContainerHighest,
      decorationPrimary: scheme.primary,
      decorationSecondary: scheme.secondary,
    );
  }

  final Color background;
  final Color surface;
  final Color raisedSurface;
  final Color textPrimary;
  final Color textSecondary;

  /// Borders of interactive elements; at least 3:1 against surfaces.
  final Color border;

  /// Decorative separators.
  final Color divider;
  final Color accentPrimary;
  final Color onAccentPrimary;
  final Color accentSecondary;
  final Color onAccentSecondary;
  final Color selection;
  final Color focus;
  final Color chartUp;
  final Color chartDown;
  final Color chartNew;
  final Color chartSteady;
  final Color storyFeatured;
  final Color onStoryFeatured;
  final Color artworkPlaceholder;
  final Color onArtworkPlaceholder;
  final Color artworkFrame;

  /// Overlay laid over artwork so text on it stays readable.
  final Color artworkScrim;
  final Color onArtworkScrim;
  final Color playbackControl;
  final Color onPlaybackControl;
  final Color progressActive;
  final Color progressInactive;
  final Color decorationPrimary;
  final Color decorationSecondary;

  @override
  SonusColors copyWith({
    Color? background,
    Color? surface,
    Color? raisedSurface,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? divider,
    Color? accentPrimary,
    Color? onAccentPrimary,
    Color? accentSecondary,
    Color? onAccentSecondary,
    Color? selection,
    Color? focus,
    Color? chartUp,
    Color? chartDown,
    Color? chartNew,
    Color? chartSteady,
    Color? storyFeatured,
    Color? onStoryFeatured,
    Color? artworkPlaceholder,
    Color? onArtworkPlaceholder,
    Color? artworkFrame,
    Color? artworkScrim,
    Color? onArtworkScrim,
    Color? playbackControl,
    Color? onPlaybackControl,
    Color? progressActive,
    Color? progressInactive,
    Color? decorationPrimary,
    Color? decorationSecondary,
  }) {
    return SonusColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      raisedSurface: raisedSurface ?? this.raisedSurface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      onAccentPrimary: onAccentPrimary ?? this.onAccentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      onAccentSecondary: onAccentSecondary ?? this.onAccentSecondary,
      selection: selection ?? this.selection,
      focus: focus ?? this.focus,
      chartUp: chartUp ?? this.chartUp,
      chartDown: chartDown ?? this.chartDown,
      chartNew: chartNew ?? this.chartNew,
      chartSteady: chartSteady ?? this.chartSteady,
      storyFeatured: storyFeatured ?? this.storyFeatured,
      onStoryFeatured: onStoryFeatured ?? this.onStoryFeatured,
      artworkPlaceholder: artworkPlaceholder ?? this.artworkPlaceholder,
      onArtworkPlaceholder: onArtworkPlaceholder ?? this.onArtworkPlaceholder,
      artworkFrame: artworkFrame ?? this.artworkFrame,
      artworkScrim: artworkScrim ?? this.artworkScrim,
      onArtworkScrim: onArtworkScrim ?? this.onArtworkScrim,
      playbackControl: playbackControl ?? this.playbackControl,
      onPlaybackControl: onPlaybackControl ?? this.onPlaybackControl,
      progressActive: progressActive ?? this.progressActive,
      progressInactive: progressInactive ?? this.progressInactive,
      decorationPrimary: decorationPrimary ?? this.decorationPrimary,
      decorationSecondary: decorationSecondary ?? this.decorationSecondary,
    );
  }

  @override
  SonusColors lerp(ThemeExtension<SonusColors>? other, double t) {
    if (other is! SonusColors) {
      return this;
    }

    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;

    return SonusColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      raisedSurface: mix(raisedSurface, other.raisedSurface),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      border: mix(border, other.border),
      divider: mix(divider, other.divider),
      accentPrimary: mix(accentPrimary, other.accentPrimary),
      onAccentPrimary: mix(onAccentPrimary, other.onAccentPrimary),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      onAccentSecondary: mix(onAccentSecondary, other.onAccentSecondary),
      selection: mix(selection, other.selection),
      focus: mix(focus, other.focus),
      chartUp: mix(chartUp, other.chartUp),
      chartDown: mix(chartDown, other.chartDown),
      chartNew: mix(chartNew, other.chartNew),
      chartSteady: mix(chartSteady, other.chartSteady),
      storyFeatured: mix(storyFeatured, other.storyFeatured),
      onStoryFeatured: mix(onStoryFeatured, other.onStoryFeatured),
      artworkPlaceholder: mix(artworkPlaceholder, other.artworkPlaceholder),
      onArtworkPlaceholder: mix(
        onArtworkPlaceholder,
        other.onArtworkPlaceholder,
      ),
      artworkFrame: mix(artworkFrame, other.artworkFrame),
      artworkScrim: mix(artworkScrim, other.artworkScrim),
      onArtworkScrim: mix(onArtworkScrim, other.onArtworkScrim),
      playbackControl: mix(playbackControl, other.playbackControl),
      onPlaybackControl: mix(onPlaybackControl, other.onPlaybackControl),
      progressActive: mix(progressActive, other.progressActive),
      progressInactive: mix(progressInactive, other.progressInactive),
      decorationPrimary: mix(decorationPrimary, other.decorationPrimary),
      decorationSecondary: mix(decorationSecondary, other.decorationSecondary),
    );
  }
}

/// Display-level text styles controlled by the typography preset. Body
/// text, titles in lists, menus and controls keep the readable [TextTheme].
@immutable
class SonusTextStyles extends ThemeExtension<SonusTextStyles> {
  const SonusTextStyles({
    required this.pageTitle,
    required this.sectionHeading,
    required this.featuredStat,
    required this.chartRank,
    required this.numeric,
  });

  factory SonusTextStyles.fromTextTheme(TextTheme textTheme) {
    const tabular = [FontFeature.tabularFigures()];

    return SonusTextStyles(
      pageTitle: textTheme.headlineMedium ?? const TextStyle(),
      sectionHeading: (textTheme.titleLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
      ),
      featuredStat: (textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFeatures: tabular,
      ),
      chartRank: (textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w800,
        fontFeatures: tabular,
      ),
      numeric: (textTheme.titleMedium ?? const TextStyle()).copyWith(
        fontFeatures: tabular,
      ),
    );
  }

  final TextStyle pageTitle;
  final TextStyle sectionHeading;
  final TextStyle featuredStat;
  final TextStyle chartRank;

  /// Durations, counts and other figures; uses tabular digits.
  final TextStyle numeric;

  @override
  SonusTextStyles copyWith({
    TextStyle? pageTitle,
    TextStyle? sectionHeading,
    TextStyle? featuredStat,
    TextStyle? chartRank,
    TextStyle? numeric,
  }) {
    return SonusTextStyles(
      pageTitle: pageTitle ?? this.pageTitle,
      sectionHeading: sectionHeading ?? this.sectionHeading,
      featuredStat: featuredStat ?? this.featuredStat,
      chartRank: chartRank ?? this.chartRank,
      numeric: numeric ?? this.numeric,
    );
  }

  @override
  SonusTextStyles lerp(ThemeExtension<SonusTextStyles>? other, double t) {
    if (other is! SonusTextStyles) {
      return this;
    }

    return SonusTextStyles(
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      sectionHeading: TextStyle.lerp(sectionHeading, other.sectionHeading, t)!,
      featuredStat: TextStyle.lerp(featuredStat, other.featuredStat, t)!,
      chartRank: TextStyle.lerp(chartRank, other.chartRank, t)!,
      numeric: TextStyle.lerp(numeric, other.numeric, t)!,
    );
  }
}

/// Spacing and corner radii. Spacing is shared by every theme; radii carry
/// each theme's framing.
@immutable
class SonusMetrics extends ThemeExtension<SonusMetrics> {
  const SonusMetrics({
    this.spaceXs = 4,
    this.spaceSm = 8,
    this.spaceMd = 12,
    this.spaceLg = 16,
    this.spaceXl = 24,
    this.pageGutter = 20,
    this.cardRadius = 14,
    this.artworkRadius = 10,
    this.controlRadius = 12,
  });

  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceLg;
  final double spaceXl;

  /// Horizontal page padding used by Home and other primary screens.
  final double pageGutter;
  final double cardRadius;
  final double artworkRadius;
  final double controlRadius;

  @override
  SonusMetrics copyWith({
    double? cardRadius,
    double? artworkRadius,
    double? controlRadius,
  }) {
    return SonusMetrics(
      spaceXs: spaceXs,
      spaceSm: spaceSm,
      spaceMd: spaceMd,
      spaceLg: spaceLg,
      spaceXl: spaceXl,
      pageGutter: pageGutter,
      cardRadius: cardRadius ?? this.cardRadius,
      artworkRadius: artworkRadius ?? this.artworkRadius,
      controlRadius: controlRadius ?? this.controlRadius,
    );
  }

  @override
  SonusMetrics lerp(ThemeExtension<SonusMetrics>? other, double t) {
    if (other is! SonusMetrics) {
      return this;
    }

    return copyWith(
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t),
      artworkRadius: lerpDouble(artworkRadius, other.artworkRadius, t),
      controlRadius: lerpDouble(controlRadius, other.controlRadius, t),
    );
  }
}

/// User-selectable decoration intensity.
enum SonusDecorationIntensity {
  off('off', 'Off'),
  subtle('subtle', 'Subtle'),
  standard('standard', 'Standard'),
  expressive('expressive', 'Expressive');

  const SonusDecorationIntensity(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static SonusDecorationIntensity? fromStorageKey(Object? key) {
    for (final value in values) {
      if (value.storageKey == key) {
        return value;
      }
    }

    return null;
  }
}

/// The effective decoration after low-effects and high-contrast limits.
@immutable
class SonusDecorationTokens extends ThemeExtension<SonusDecorationTokens> {
  const SonusDecorationTokens({
    required this.intensity,
    required this.motif,
    required this.markOpacity,
    required this.showTexture,
    required this.textureOpacity,
    required this.allowGlow,
    required this.allowGradients,
    this.progressStyle = SonusProgressStyle.minimalLinear,
  });

  /// No decoration at all; used when no Sonus theme is installed.
  const SonusDecorationTokens.none()
    : intensity = SonusDecorationIntensity.off,
      motif = SonusMotif.geometric,
      markOpacity = 0,
      showTexture = false,
      textureOpacity = 0,
      allowGlow = false,
      allowGradients = false,
      progressStyle = SonusProgressStyle.minimalLinear;

  final SonusDecorationIntensity intensity;
  final SonusMotif motif;

  /// Opacity of heading marks and featured-section accents.
  final double markOpacity;
  final bool showTexture;
  final double textureOpacity;
  final bool allowGlow;
  final bool allowGradients;

  /// The theme's playback progress treatment (SN-48E).
  final SonusProgressStyle progressStyle;

  bool get showMarks => intensity != SonusDecorationIntensity.off;

  @override
  SonusDecorationTokens copyWith({
    SonusDecorationIntensity? intensity,
    double? markOpacity,
  }) {
    return SonusDecorationTokens(
      intensity: intensity ?? this.intensity,
      motif: motif,
      markOpacity: markOpacity ?? this.markOpacity,
      showTexture: showTexture,
      textureOpacity: textureOpacity,
      allowGlow: allowGlow,
      allowGradients: allowGradients,
      progressStyle: progressStyle,
    );
  }

  @override
  SonusDecorationTokens lerp(
    ThemeExtension<SonusDecorationTokens>? other,
    double t,
  ) {
    if (other is! SonusDecorationTokens) {
      return this;
    }

    return t < 0.5 ? this : other;
  }
}

/// Animation timing. Durations collapse to zero when motion is reduced.
@immutable
class SonusMotion extends ThemeExtension<SonusMotion> {
  const SonusMotion({
    required this.reduced,
    required this.curve,
    this.baseShort = const Duration(milliseconds: 150),
    this.baseMedium = const Duration(milliseconds: 250),
    this.baseLong = const Duration(milliseconds: 400),
  });

  final bool reduced;
  final Curve curve;
  final Duration baseShort;
  final Duration baseMedium;
  final Duration baseLong;

  Duration get short => reduced ? Duration.zero : baseShort;
  Duration get medium => reduced ? Duration.zero : baseMedium;
  Duration get long => reduced ? Duration.zero : baseLong;

  @override
  SonusMotion copyWith({bool? reduced, Curve? curve}) {
    return SonusMotion(
      reduced: reduced ?? this.reduced,
      curve: curve ?? this.curve,
      baseShort: baseShort,
      baseMedium: baseMedium,
      baseLong: baseLong,
    );
  }

  @override
  SonusMotion lerp(ThemeExtension<SonusMotion>? other, double t) {
    if (other is! SonusMotion) {
      return this;
    }

    return t < 0.5 ? this : other;
  }
}
