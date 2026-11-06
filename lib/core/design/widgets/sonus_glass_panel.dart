import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';
import '../sonus_tokens.dart';

/// Glow shadows that respect the user's settings: none where glow is not
/// allowed (Decoration Off or Subtle, High contrast, Low effects) or the
/// colour is transparent.
abstract final class SonusGlow {
  static List<BoxShadow> shadows(
    Color glow,
    SonusDecorationTokens decoration, {
    double blurRadius = 28,
    double spreadRadius = 1,
  }) {
    if (!decoration.allowGlow || glow.a == 0) return const [];
    return [
      BoxShadow(
        color: glow,
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
      ),
    ];
  }
}

/// A translucent "glass" panel (UI redesign D13): simulated, not a live
/// blur. A light-to-clear fill over [base], a thin [edge] rim and an
/// optional [glow].
///
/// Where gradients are not allowed (Decoration Off, High contrast, Low
/// effects) the panel is an opaque [base] with a solid [edge] border and
/// no glow, so text on it keeps the contrast its colours were chosen for.
/// [backdropBlur] adds a real blur of what lies behind; it is meant for
/// panels that stay still, and applies only where glow is allowed.
class SonusGlassPanel extends StatelessWidget {
  const SonusGlassPanel({
    super.key,
    required this.base,
    required this.edge,
    required this.child,
    this.glow,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = const EdgeInsets.all(16),
    this.backdropBlur = false,
  });

  /// The panel's colour; fully opaque where glass effects are off.
  final Color base;

  /// The rim.
  final Color edge;

  /// Shadow colour around the panel, if any.
  final Color? glow;

  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Blurs what lies behind the panel, where glow is allowed. Costly on
  /// some phones: use only for panels that do not move.
  final bool backdropBlur;

  final Widget child;

  /// Blur strength of [backdropBlur].
  static const double blurSigma = 12;

  @override
  Widget build(BuildContext context) {
    final decoration = SonusTheme.of(context).decoration;
    final glass = decoration.allowGradients;
    final glow = this.glow;

    final panel = DecoratedBox(
      key: const ValueKey<String>('sonus-glass-panel-surface'),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: glass ? null : base.withValues(alpha: 1),
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    base,
                    const Color(0xFFFFFFFF),
                    0.10,
                  )!.withValues(alpha: 0.74),
                  base.withValues(alpha: 0.56),
                ],
              )
            : null,
        border: Border.all(color: edge, width: glass ? 1 : 1.5),
        boxShadow: glow == null ? null : SonusGlow.shadows(glow, decoration),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!glass || !backdropBlur || !decoration.allowGlow) return panel;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        key: const ValueKey<String>('sonus-glass-panel-blur'),
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: panel,
      ),
    );
  }
}
