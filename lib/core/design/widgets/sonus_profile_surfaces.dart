import 'package:flutter/material.dart';

import '../sonus_profile_colors.dart';
import '../sonus_theme.dart';

/// The page behind an Artist or Album Profile (UI redesign V1, V2): the
/// artwork's colour from top to bottom, lit by a few soft pools of its
/// light, so the whole page is the artwork's environment rather than a
/// dark page with colour at the top. It stays still behind the scrolling
/// content, so the atmosphere is there however far the page scrolls.
///
/// Colour only: the image itself is never drawn here (roadmap D3). Radial
/// gradients are cheap to paint, and a [RepaintBoundary] keeps them from
/// repainting with the content. Flat theme colour where the profile is
/// untinted, as it is under Decoration Off, High contrast and Low effects.
class SonusProfileBackdrop extends StatelessWidget {
  const SonusProfileBackdrop({
    super.key,
    required this.profile,
    required this.child,
    this.baseKey,
    this.environment,
  });

  final SonusProfileColors profile;
  final Widget child;

  /// Drawn over the ground, under the light pools: for example the
  /// artwork environment (SonusArtworkEnvironment). None by default.
  final Widget? environment;

  /// A key for the base colour layer, for tests and screen captures.
  final Key? baseKey;

  @override
  Widget build(BuildContext context) {
    final base = DecoratedBox(
      key: baseKey,
      decoration: BoxDecoration(
        color: profile.isTinted ? null : profile.background,
        gradient: profile.isTinted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [profile.background, profile.backgroundDeep],
                stops: const [0.2, 1],
              )
            : null,
      ),
      child: const SizedBox.expand(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                base,
                ?environment,
                if (profile.isTinted) ...[
                  _Light(
                    key: const ValueKey<String>('sonus-profile-light-high'),
                    center: const Alignment(0.95, -0.85),
                    radius: 0.95,
                    colour: profile.light,
                    alpha: SonusProfileColors.ambientAlpha,
                  ),
                  _Light(
                    center: const Alignment(-1.05, 0.05),
                    radius: 0.85,
                    colour: profile.accent,
                    alpha: SonusProfileColors.ambientAlpha * 0.55,
                  ),
                  _Light(
                    center: const Alignment(0.7, 0.95),
                    radius: 1.1,
                    colour: profile.light,
                    alpha: SonusProfileColors.ambientAlpha * 0.7,
                  ),
                ],
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    super.key,
    required this.center,
    required this.radius,
    required this.colour,
    required this.alpha,
  });

  final Alignment center;
  final double radius;
  final Color colour;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: center,
          radius: radius,
          colors: [
            colour.withValues(alpha: alpha),
            colour.withValues(alpha: alpha * 0.4),
            colour.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

/// A soft glass surface for profile sections (UI redesign V1, V2): the
/// artwork-tinted [SonusProfileColors.surface], translucent over the page,
/// with a faint highlight at the top and a barely-there rim. No heavy
/// outline and no drop shadow (a shadow would show through the glass):
/// sections are separated by colour, light and spacing.
///
/// Where gradients are not allowed (Decoration Off, High contrast, Low
/// effects) it is the opaque surface with a solid, visible border and no
/// shadow, so text keeps the contrast its colours were chosen for.
class SonusSoftGlass extends StatelessWidget {
  const SonusSoftGlass({
    super.key,
    required this.profile,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding = const EdgeInsets.all(8),
  });

  final SonusProfileColors profile;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final glass = tokens.decoration.allowGradients;

    return DecoratedBox(
      key: const ValueKey<String>('sonus-soft-glass-surface'),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: glass ? null : profile.surface.withValues(alpha: 1),
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    const Color(
                      0xFFFFFFFF,
                    ).withValues(alpha: SonusProfileColors.glassHighlight),
                    profile.surface.withValues(
                      alpha: SonusProfileColors.glassAlpha,
                    ),
                  ),
                  profile.surface.withValues(
                    alpha: SonusProfileColors.glassAlpha,
                  ),
                ],
                stops: const [0, 0.35],
              )
            : null,
        border: Border.all(
          color: glass
              ? profile.edge.withValues(alpha: 0.22)
              : tokens.colors.border,
          width: glass ? 0.8 : 1.5,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
