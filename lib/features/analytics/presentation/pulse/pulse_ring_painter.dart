import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import 'pulse_colors.dart';
import 'pulse_ring_layout.dart';

/// One spoke as drawn in the current animation frame.
@immutable
class PulseSpokeFrame {
  const PulseSpokeFrame({
    required this.state,
    required this.fraction,
    required this.tip,
    required this.itemFraction,
    required this.ghostFraction,
    required this.hasValue,
  });

  final PulseDayState state;
  final double fraction;
  final Color tip;
  final double itemFraction;
  final double? ghostFraction;
  final bool hasValue;
}

/// Paints the Pulse ring. Purely presentational: every length and colour
/// comes from [PulseRingLayout] (real data), interpolated by the hero's
/// animations only between two real states.
class PulseRingPainter extends CustomPainter {
  PulseRingPainter({
    required this.period,
    required this.spokes,
    required this.palette,
    required this.ramp,
    required this.averageFraction,
    required this.ghostOpacity,
    required this.itemActive,
    required this.itemColor,
    required this.selected,
    required this.haloColor,
  });

  final PulsePeriod period;
  final List<PulseSpokeFrame> spokes;
  final PulsePalette palette;
  final PulseRamp ramp;
  final double averageFraction;
  final double ghostOpacity;
  final bool itemActive;
  final Color itemColor;
  final int? selected;
  final Color haloColor;

  /// Others dim to 55% around a selected day, and to 62% around an open
  /// item (spec §3.1–3.2).
  static const double dayDim = 0.55;
  static const double itemDim = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final g = PulseRingGeometry.of(period, size);
    final len = g.maxLength;

    if (palette.haloStrength > 0) {
      canvas.drawCircle(
        g.center,
        g.outerRadius * 1.08,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  haloColor.withValues(alpha: palette.haloStrength),
                  haloColor.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(center: g.center, radius: g.outerRadius * 1.08),
              ),
      );
    }

    canvas.drawCircle(
      g.center,
      g.innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.textSecondary.withValues(alpha: 0.28),
    );

    if (averageFraction > 0) {
      final r = g.innerRadius + averageFraction * len;
      final dots = (2 * math.pi * r / 7).floor().clamp(12, 400);
      final dotPaint = Paint()
        ..color = palette.textSecondary.withValues(alpha: 0.5);
      for (var i = 0; i < dots; i++) {
        canvas.drawCircle(g.point(2 * math.pi * i / dots, r), 0.9, dotPaint);
      }
    }

    // Comparison ghost: dashed, lightest step, same scale.
    if (ghostOpacity > 0) {
      final ghostPaint = Paint()
        ..strokeWidth = math.max(1, g.spokeWidth * 0.6)
        ..strokeCap = StrokeCap.butt
        ..color = (palette.highContrast ? palette.textSecondary : ramp.lightest)
            .withValues(alpha: 0.5 * ghostOpacity);
      for (var i = 0; i < spokes.length; i++) {
        final ghost = spokes[i].ghostFraction;
        if (ghost == null || ghost <= 0) continue;
        _dashed(
          canvas,
          g.point(g.angles[i], g.innerRadius),
          g.point(g.angles[i], g.innerRadius + ghost * len),
          ghostPaint,
        );
      }
    }

    final dim = selected != null
        ? dayDim
        : itemActive
        ? itemDim
        : 1.0;

    for (var i = 0; i < spokes.length; i++) {
      final spoke = spokes[i];
      final angle = g.angles[i];
      final start = g.point(angle, g.innerRadius);
      final isSelected = selected == i;
      switch (spoke.state) {
        case PulseDayState.future:
          continue;
        case PulseDayState.beforeHistory:
          // A short hatched stub: never a zero (rule 2).
          final hatch = Paint()
            ..strokeWidth = math.max(1, g.spokeWidth * 0.5)
            ..color = palette.textSecondary.withValues(
              alpha: (isSelected ? 0.9 : 0.35),
            );
          for (var k = 0; k < 3; k++) {
            canvas.drawLine(
              g.point(angle, g.innerRadius + 2 + k * 4),
              g.point(angle, g.innerRadius + 4 + k * 4),
              hatch,
            );
          }
          continue;
        case PulseDayState.recorded:
          break;
      }

      if (!spoke.hasValue || spoke.fraction <= 0) {
        canvas.drawCircle(
          start,
          math.max(1.2, g.spokeWidth * 0.45),
          Paint()
            ..color = (isSelected ? palette.text : palette.textSecondary)
                .withValues(alpha: isSelected ? 1 : 0.6 * dim),
        );
        continue;
      }

      final end = g.point(angle, g.innerRadius + spoke.fraction * len);
      final alpha = isSelected ? 1.0 : dim;
      final paint = Paint()
        ..strokeWidth = g.spokeWidth
        ..strokeCap = StrokeCap.round;

      if (isSelected) {
        if (palette.allowGlow) {
          canvas.drawLine(
            start,
            end,
            Paint()
              ..strokeWidth = g.spokeWidth * 2.6
              ..strokeCap = StrokeCap.round
              ..color = palette.text.withValues(alpha: 0.28)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }
        paint.color = palette.text;
      } else if (ramp.fill == PulseFill.gradient) {
        // Along the spoke itself: base at the inner ring, tip outward.
        paint.shader = ui.Gradient.linear(start, end, [
          ramp.base.withValues(alpha: alpha),
          spoke.tip.withValues(alpha: alpha),
        ]);
      } else {
        paint.color = spoke.tip.withValues(alpha: alpha);
      }
      canvas.drawLine(start, end, paint);

      if (isSelected && palette.highContrast) {
        canvas.drawCircle(
          end,
          g.spokeWidth,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = palette.text,
        );
      }

      // The selected item's part, from the inner ring outward; a subset of
      // the spoke by construction.
      if (itemActive && spoke.itemFraction > 0) {
        final itemEnd = g.point(
          angle,
          g.innerRadius + spoke.itemFraction * len,
        );
        if (palette.allowGlow) {
          canvas.drawLine(
            start,
            itemEnd,
            Paint()
              ..strokeWidth = g.spokeWidth * 2.2
              ..strokeCap = StrokeCap.round
              ..color = itemColor.withValues(alpha: 0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
        canvas.drawLine(
          start,
          itemEnd,
          Paint()
            ..strokeWidth = palette.itemOutlineOnly
                ? g.spokeWidth + 1.5
                : g.spokeWidth
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke
            ..color = itemColor,
        );
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    const dash = 3.0;
    const gap = 3.0;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
    }
  }

  @override
  bool shouldRepaint(PulseRingPainter old) =>
      old.spokes != spokes ||
      old.selected != selected ||
      old.ghostOpacity != ghostOpacity ||
      old.itemActive != itemActive ||
      old.itemColor != itemColor ||
      old.palette != palette ||
      old.ramp != ramp ||
      old.period != period ||
      old.averageFraction != averageFraction ||
      old.haloColor != haloColor;
}
