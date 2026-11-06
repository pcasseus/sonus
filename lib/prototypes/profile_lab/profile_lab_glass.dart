// Artist Profile Lab: glass plates.
//
// PROTOTYPE ONLY (see profile_lab_models.dart).
//
// The plate is its own material, not the page colour at another alpha:
// - a tinted fill darker and more even than the lit backdrop, so text on
//   it has a local ground;
// - a soft sheen from the top-left, as light catching the surface;
// - a rim that fades from lit (top) to almost nothing (bottom), instead of
//   an even white outline;
// - a soft shadow that lifts it off the backdrop.
// No live blur: the backdrop behind it is already blurred.
import 'package:flutter/material.dart';

import 'profile_lab_atmosphere.dart';

class LabGlass extends StatelessWidget {
  const LabGlass({
    super.key,
    required this.atmosphere,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.layers = LabLayers.all,
    this.shape = BoxShape.rectangle,
    this.raised = true,
  });

  final LabAtmosphere atmosphere;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final LabLayers layers;
  final BoxShape shape;

  /// Casts the soft shadow (cards); small chips and buttons do not.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    if (!layers.glass) return Padding(padding: padding, child: child);
    final circle = shape == BoxShape.circle;
    final borderRadius = circle ? null : BorderRadius.circular(radius);

    if (!a.effects) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: a.glass,
          shape: shape,
          borderRadius: borderRadius,
          border: Border.all(color: a.glassRim, width: a.highContrast ? 2 : 1),
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    return CustomPaint(
      foregroundPainter: _RimPainter(
        colour: a.glassRim,
        radius: radius,
        circle: circle,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: borderRadius,
          color: a.glass,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                const Color(0xFFFFFFFF).withValues(alpha: 0.07),
                a.glass,
              ),
              a.glass,
              a.glass,
            ],
            stops: const [0, 0.45, 1],
          ),
          boxShadow: raised
              ? [
                  BoxShadow(
                    color: a.groundDeep.withValues(alpha: 0.55),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.colour,
    required this.radius,
    required this.circle,
  });

  final Color colour;
  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final paint = Paint()
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
      ).createShader(rect);
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.colour != colour ||
      oldDelegate.radius != radius ||
      oldDelegate.circle != circle;
}
