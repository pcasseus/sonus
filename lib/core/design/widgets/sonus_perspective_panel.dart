import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// Tilts [child] in 3D around its vertical axis, like the angled statistics
/// panels beside the Film Reel portrait (UI redesign). A positive [angle]
/// turns the right edge away from the viewer; [alignment] is the hinge.
///
/// Decorative only: layout, hit testing and semantics are those of
/// [child]. Where gradients are not allowed (Decoration Off, High
/// contrast, Low effects) the panel stays flat, so its text is never
/// foreshortened.
class SonusPerspectivePanel extends StatelessWidget {
  const SonusPerspectivePanel({
    super.key,
    required this.angle,
    required this.child,
    this.alignment = Alignment.center,
    this.depth = defaultDepth,
  });

  /// Rotation around the vertical axis, in radians.
  final double angle;

  /// The hinge the panel turns around.
  final AlignmentGeometry alignment;

  /// Perspective strength: larger values look closer.
  final double depth;

  final Widget child;

  static const double defaultDepth = 0.0015;

  /// The tilt actually used in [context]: [angle], or 0 where it must stay
  /// flat.
  static double effectiveAngle(BuildContext context, double angle) =>
      SonusTheme.of(context).decoration.allowGradients ? angle : 0;

  @override
  Widget build(BuildContext context) {
    final tilt = effectiveAngle(context, angle);
    if (tilt == 0) return child;

    return Transform(
      key: const ValueKey<String>('sonus-perspective-panel-transform'),
      alignment: alignment,
      transform: Matrix4.identity()
        ..setEntry(3, 2, depth)
        ..rotateY(tilt),
      child: child,
    );
  }
}
