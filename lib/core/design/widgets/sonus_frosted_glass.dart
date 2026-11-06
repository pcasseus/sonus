import 'package:flutter/material.dart';

/// A frosted glass plate (Artist Profile Lab method, approved 2026-11-06).
///
/// - A screen-blended lift raises whatever is behind the plate by about the
///   same amount, so the plate stays visible over dark and bright artwork
///   alike (a fixed fill colour cannot).
/// - A thin [tint] in the page's hue, and a soft sheen from the top.
/// - A rim that fades from lit at the top to almost nothing at the bottom,
///   instead of an even outline.
/// - A soft shadow painted outside the plate only: under translucent glass a
///   box shadow would show through and dull it.
///
/// Where effects are off ([frosted] false: Decoration Off, High contrast,
/// Low effects) it is a solid [solid] plate with a plain [edge].
class SonusFrostedGlass extends StatelessWidget {
  const SonusFrostedGlass({
    super.key,
    required this.child,
    required this.frosted,
    required this.tint,
    required this.light,
    required this.shadow,
    required this.solid,
    required this.edge,
    this.borderRadius = 22,
    this.padding = EdgeInsets.zero,
    this.raised = true,
  });

  final Widget child;
  final bool frosted;

  /// The plate's tint (translucent) and its light (for the lift and rim).
  final Color tint;
  final Color light;

  /// The shadow under the plate's lower edge.
  final Color shadow;

  /// The opaque plate and its edge without effects.
  final Color solid;
  final Color edge;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  /// Casts the soft outer shadow.
  final bool raised;

  static const double liftAlpha = 0.09;
  static const double tintAlpha = 0.06;
  static const double rimAlpha = 0.10;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    if (!frosted) {
      return DecoratedBox(
        key: const ValueKey<String>('sonus-frosted-glass-surface'),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: solid.withValues(alpha: 1),
          border: Border.all(color: edge),
        ),
        child: Padding(padding: padding, child: child),
      );
    }
    final lift = Color.lerp(
      const Color(0xFFFFFFFF),
      light,
      0.35,
    )!.withValues(alpha: liftAlpha);
    final fill = tint.withValues(alpha: tintAlpha);
    return CustomPaint(
      painter: raised
          ? _OuterShadowPainter(
              colour: shadow.withValues(alpha: 0.38),
              radius: borderRadius,
            )
          : null,
      foregroundPainter: _RimPainter(
        colour: const Color(0xFFFFFFFF).withValues(alpha: rimAlpha),
        radius: borderRadius,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: lift,
          backgroundBlendMode: BlendMode.screen,
        ),
        child: DecoratedBox(
          key: const ValueKey<String>('sonus-frosted-glass-surface'),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  const Color(0xFFFFFFFF).withValues(alpha: 0.05),
                  fill,
                ),
                fill,
                fill,
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({required this.colour, required this.radius});

  final Color colour;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final plate = Offset.zero & size;
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(plate, Radius.circular(radius)));
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(plate.inflate(60))
        ..addPath(shape, Offset.zero),
    );
    canvas.drawPath(
      shape.shift(const Offset(0, 8)),
      Paint()
        ..color = colour
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.radius != radius;
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.colour, required this.radius});

  final Color colour;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colour,
            colour.withValues(alpha: colour.a * 0.35),
            colour.withValues(alpha: colour.a * 0.12),
          ],
          stops: const [0, 0.4, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.radius != radius;
}
