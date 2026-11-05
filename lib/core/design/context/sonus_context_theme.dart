import 'package:flutter/material.dart';

import '../sonus_profile_colors.dart';
import '../sonus_tokens.dart';

/// The colours of the place a widget sits in (theme architecture T0): the
/// page's own ground, surface and accent. Most of Sonus sits on the theme
/// itself; an artwork-adaptive page (an Artist or Album Profile) supplies
/// its artwork's colours instead.
@immutable
class SonusContextColors {
  const SonusContextColors({
    required this.background,
    required this.surface,
    required this.raisedSurface,
    required this.edge,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.isTinted,
  });

  /// The theme itself: nothing is re-themed.
  factory SonusContextColors.theme(SonusColors colors) => SonusContextColors(
    background: colors.background,
    surface: colors.surface,
    raisedSurface: colors.raisedSurface,
    edge: colors.border,
    accent: colors.accentPrimary,
    onAccent: colors.onAccentPrimary,
    textPrimary: colors.textPrimary,
    textSecondary: colors.textSecondary,
    isTinted: false,
  );

  /// An artwork-adaptive profile page. Untinted profile colours (no
  /// artwork yet, or accessibility settings that keep the theme flat) give
  /// the theme's own context.
  factory SonusContextColors.profile(
    SonusProfileColors profile, {
    required SonusColors theme,
  }) {
    if (!profile.isTinted) return SonusContextColors.theme(theme);
    return SonusContextColors(
      background: profile.background,
      surface: profile.surface,
      // Menus, dialogs and sheets float above the page: a step lighter
      // than its glass, in the page's own hue.
      raisedSurface: Color.lerp(profile.surface, theme.textPrimary, 0.06)!,
      edge: profile.edge,
      accent: profile.accent,
      onAccent: profile.onAccent,
      textPrimary: profile.textPrimary,
      textSecondary: profile.textSecondary,
      isTinted: true,
    );
  }

  final Color background;

  /// Cards, rows and glass.
  final Color surface;

  /// Menus, dialogs and sheets.
  final Color raisedSurface;

  /// Rims and outlines.
  final Color edge;
  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;

  /// Whether these differ from the theme: an artwork-adaptive context.
  final bool isTinted;

  @override
  bool operator ==(Object other) =>
      other is SonusContextColors &&
      other.background == background &&
      other.surface == surface &&
      other.raisedSurface == raisedSurface &&
      other.edge == edge &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.isTinted == isTinted;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    raisedSurface,
    edge,
    accent,
    onAccent,
    textPrimary,
    textSecondary,
    isTinted,
  );
}

/// Re-themes a subtree from its [SonusContextColors] (theme architecture
/// T0, the audit's "contextual colours" layer).
///
/// Inside a tinted context every Sonus token and Material component
/// follows the page: [SonusTheme.of] reports the page's background,
/// surface and accent, and menus, dialogs, bottom sheets, checkboxes,
/// buttons, progress indicators and selection take the artwork's colours
/// instead of the theme's blue and charcoal. Dialogs, sheets and menus
/// opened from inside inherit it (Flutter captures inherited themes when
/// it shows them).
///
/// Outside a tinted context nothing changes: screens that use the theme
/// look exactly as before. Accessibility needs no special case here: the
/// resolvers already return untinted colours when gradients are not
/// allowed (Decoration Off, High contrast, Low effects).
class SonusContextTheme extends StatelessWidget {
  const SonusContextTheme({
    super.key,
    required this.colors,
    required this.child,
  });

  final SonusContextColors colors;
  final Widget child;

  /// The context colours [context] sits in: the nearest
  /// [SonusContextTheme], or the theme's own.
  static SonusContextColors of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SonusContextScope>();
    if (scope != null) return scope.colors;
    return SonusContextColors.theme(
      Theme.of(context).extension<SonusColors>()!,
    );
  }

  /// [base] re-themed for [colors]; [base] itself when untinted.
  static ThemeData themeFor(ThemeData base, SonusContextColors colors) {
    if (!colors.isTinted) return base;

    final sonus = base.extension<SonusColors>()!;
    final selection = colors.accent.withValues(alpha: 0.22);
    final tonal = Color.alphaBlend(
      colors.accent.withValues(alpha: 0.24),
      colors.surface,
    );
    final contextual = sonus.copyWith(
      background: colors.background,
      surface: colors.surface,
      raisedSurface: colors.raisedSurface,
      textPrimary: colors.textPrimary,
      textSecondary: colors.textSecondary,
      border: colors.edge,
      accentPrimary: colors.accent,
      onAccentPrimary: colors.onAccent,
      selection: selection,
      progressActive: colors.accent,
      playbackControl: colors.accent,
      onPlaybackControl: colors.onAccent,
    );

    final scheme = base.colorScheme.copyWith(
      primary: colors.accent,
      onPrimary: colors.onAccent,
      primaryContainer: tonal,
      onPrimaryContainer: colors.textPrimary,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      secondaryContainer: tonal,
      onSecondaryContainer: colors.textPrimary,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.raisedSurface,
      surfaceContainerHigh: colors.raisedSurface,
      outline: colors.edge,
      outlineVariant: colors.edge,
      surfaceTint: Colors.transparent,
    );

    return base.copyWith(
      colorScheme: scheme,
      canvasColor: colors.background,
      cardColor: colors.surface,
      dividerColor: colors.edge,
      extensions: [
        for (final extension in base.extensions.values)
          if (extension is SonusColors) contextual else extension,
      ],
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: colors.raisedSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: colors.raisedSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: colors.raisedSurface,
        modalBackgroundColor: colors.raisedSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: colors.accent,
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? colors.accent : null,
        ),
        checkColor: WidgetStatePropertyAll(colors.onAccent),
      ),
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: colors.accent,
        selectionColor: selection,
        selectionHandleColor: colors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return _SonusContextScope(
      colors: colors,
      child: colors.isTinted
          ? Theme(data: themeFor(base, colors), child: child)
          : child,
    );
  }
}

class _SonusContextScope extends InheritedWidget {
  const _SonusContextScope({required this.colors, required super.child});

  final SonusContextColors colors;

  @override
  bool updateShouldNotify(_SonusContextScope oldWidget) =>
      oldWidget.colors != colors;
}
