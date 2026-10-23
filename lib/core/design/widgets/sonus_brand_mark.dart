import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';
import '../sonus_theme_catalog.dart';
import '../sonus_theme_id.dart';

/// The Sonus logo concepts explored in SN-48.
///
/// [waveformS] is the approved Sonus brand mark ([selected]) and the
/// direction for the future launcher icon. The other two are kept for
/// design reference only.
enum SonusBrandConcept {
  /// A letter S drawn as three waveform strokes that meet at its centre.
  waveformS('Waveform S'),

  /// A bold S whose two ends emit sound waves.
  soundWaveS('S + Sound Waves'),

  /// Equalizer bars whose rhythm traces an S-shaped signal.
  signal('Sonus Signal');

  const SonusBrandConcept(this.label);

  final String label;

  /// The official Sonus brand mark.
  static const SonusBrandConcept selected = waveformS;
}

enum SonusBrandMarkStyle {
  /// Concrete & Spray's electric blue and spray pink.
  accent,

  /// A single colour, for themed launchers, notifications and print.
  monochrome,

  /// The active theme's primary and secondary accents. Under Concrete &
  /// Spray this is the signature blue and pink; Monochrome renders it in
  /// white and grey.
  theme,
}

/// The Sonus logo mark, drawn as vectors so it stays crisp from launcher
/// size to splash size.
class SonusBrandMark extends StatelessWidget {
  const SonusBrandMark({
    super.key,
    required this.concept,
    this.style = SonusBrandMarkStyle.accent,
    this.size = 48,
    this.color,
  });

  final SonusBrandConcept concept;
  final SonusBrandMarkStyle style;
  final double size;

  /// The monochrome colour; defaults to the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final (primary, secondary) = _colors(context);

    return Semantics(
      label: 'Sonus',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: SonusBrandMarkPainter(
          concept: concept,
          primary: primary,
          secondary: secondary,
        ),
      ),
    );
  }

  (Color, Color) _colors(BuildContext context) {
    switch (style) {
      case SonusBrandMarkStyle.accent:
        final palette = SonusThemeCatalog.of(
          SonusThemeId.concreteSpray,
        ).palette;
        return (palette.primary, palette.secondary);
      case SonusBrandMarkStyle.monochrome:
        final mono = color ?? IconTheme.of(context).color ?? Colors.white;
        return (mono, mono);
      case SonusBrandMarkStyle.theme:
        final colors = SonusTheme.of(context).colors;
        return (colors.accentPrimary, colors.accentSecondary);
    }
  }
}

/// Paints one concept inside a square; geometry is in unit coordinates.
class SonusBrandMarkPainter extends CustomPainter {
  const SonusBrandMarkPainter({
    required this.concept,
    required this.primary,
    required this.secondary,
  });

  final SonusBrandConcept concept;
  final Color primary;
  final Color secondary;

  /// The shared S spine: top-right terminal, over the top, through the
  /// centre and round to the bottom-left terminal.
  static Path _spine(double s) => Path()
    ..moveTo(0.72 * s, 0.24 * s)
    ..cubicTo(0.62 * s, 0.12 * s, 0.30 * s, 0.12 * s, 0.30 * s, 0.32 * s)
    ..cubicTo(0.30 * s, 0.48 * s, 0.70 * s, 0.46 * s, 0.70 * s, 0.66 * s)
    ..cubicTo(0.70 * s, 0.88 * s, 0.38 * s, 0.88 * s, 0.28 * s, 0.76 * s);

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    switch (concept) {
      case SonusBrandConcept.waveformS:
        _paintWaveformS(canvas, s);
      case SonusBrandConcept.soundWaveS:
        _paintSoundWaveS(canvas, s);
      case SonusBrandConcept.signal:
        _paintSignal(canvas, s);
    }
  }

  void _paintWaveformS(Canvas canvas, double s) {
    final spine = _spine(s);
    final centre = Offset(s / 2, s / 2);

    // Two echoes of the S, scaled about its centre, so all three strokes
    // cross at one node like overlapping waveforms.
    for (final scale in const [0.62, 1.34]) {
      final echo = spine.transform(
        (Matrix4.identity()
              ..translateByDouble(centre.dx, centre.dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1)
              ..translateByDouble(-centre.dx, -centre.dy, 0, 1))
            .storage,
      );
      canvas.drawPath(_trim(echo, 0.12, 0.88), _stroke(secondary, s * 0.045));
    }

    canvas.drawPath(spine, _stroke(primary, s * 0.095));
  }

  void _paintSoundWaveS(Canvas canvas, double s) {
    canvas.drawPath(_spine(s), _stroke(primary, s * 0.14));

    final waves = _stroke(secondary, s * 0.05);
    const sweep = math.pi * 0.42;

    // Waves leave the upper terminal towards the top right and the lower
    // terminal towards the bottom left.
    for (final (centre, start) in [
      (Offset(0.72 * s, 0.24 * s), -math.pi * 0.46),
      (Offset(0.28 * s, 0.76 * s), math.pi * 0.54),
    ]) {
      for (final radius in [0.12 * s, 0.2 * s]) {
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: radius),
          start,
          sweep,
          false,
          waves,
        );
      }
    }
  }

  void _paintSignal(Canvas canvas, double s) {
    // Bar heights give the rhythm; their centres ride one period of a
    // wave, which reads as an S turned on its side.
    const heights = [0.22, 0.32, 0.40, 0.30, 0.40, 0.32, 0.22];
    const count = 7;
    final barWidth = s * 0.075;

    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final x = s * (0.2 + 0.6 * t);
      final y = s * (0.5 - 0.2 * math.sin(t * 2 * math.pi));
      final h = s * heights[i];

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: barWidth, height: h),
          Radius.circular(barWidth / 2),
        ),
        Paint()..color = Color.lerp(primary, secondary, t)!,
      );
    }
  }

  static Path _trim(Path path, double from, double to) {
    final trimmed = Path();

    for (final metric in path.computeMetrics()) {
      trimmed.addPath(
        metric.extractPath(metric.length * from, metric.length * to),
        Offset.zero,
      );
    }

    return trimmed;
  }

  @override
  bool shouldRepaint(SonusBrandMarkPainter oldDelegate) =>
      oldDelegate.concept != concept ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary;
}
