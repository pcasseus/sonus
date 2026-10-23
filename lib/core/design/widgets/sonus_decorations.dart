import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';
import '../sonus_theme_definition.dart';

/// A small decorative mark in the active theme's motif, drawn under major
/// headings and featured sections.
///
/// Purely decorative: it is excluded from semantics, draws nothing when
/// decoration is off, and never animates.
class SonusMotifMark extends StatelessWidget {
  const SonusMotifMark({super.key, this.width = 56, this.height = 10});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final decoration = tokens.decoration;

    if (!decoration.showMarks) {
      return const SizedBox.shrink();
    }

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey<String>('sonus-motif-mark'),
          size: Size(width, height),
          painter: SonusMotifPainter(
            motif: decoration.motif,
            primary: tokens.colors.decorationPrimary,
            secondary: tokens.colors.decorationSecondary,
            opacity: decoration.markOpacity,
            allowGlow: decoration.allowGlow,
            allowGradients: decoration.allowGradients,
          ),
        ),
      ),
    );
  }
}

/// Draws one motif. Shapes are fixed, so repeated paints are identical.
class SonusMotifPainter extends CustomPainter {
  const SonusMotifPainter({
    required this.motif,
    required this.primary,
    required this.secondary,
    required this.opacity,
    required this.allowGlow,
    required this.allowGradients,
  });

  final SonusMotif motif;
  final Color primary;
  final Color secondary;
  final double opacity;
  final bool allowGlow;
  final bool allowGradients;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final main = primary.withValues(alpha: opacity);
    final accent = secondary.withValues(alpha: opacity);

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    Paint fill(Color color) => Paint()..color = color;

    switch (motif) {
      case SonusMotif.spray:
        final path = Path()
          ..moveTo(h * 0.3, h * 0.45)
          ..quadraticBezierTo(w * 0.35, h * 0.15, w * 0.62, h * 0.4)
          ..quadraticBezierTo(w * 0.78, h * 0.55, w * 0.88, h * 0.35);
        canvas.drawPath(path, stroke(main, h * 0.42));
        // A short drip and an overspray dot.
        canvas.drawLine(
          Offset(w * 0.6, h * 0.5),
          Offset(w * 0.6, h * 0.95),
          stroke(main, h * 0.16),
        );
        canvas.drawCircle(Offset(w * 0.96, h * 0.2), h * 0.1, fill(accent));
      case SonusMotif.sticker:
        final rect = RRect.fromLTRBR(
          0,
          0,
          w * 0.7,
          h * 0.8,
          Radius.circular(2),
        );
        canvas.drawRRect(rect.shift(const Offset(2, 2)), fill(accent));
        canvas.drawRRect(rect, fill(main));
        // A strip of tape across the corner.
        canvas.drawRect(
          Rect.fromLTWH(w * 0.74, h * 0.15, w * 0.2, h * 0.5),
          fill(accent.withValues(alpha: opacity * 0.6)),
        );
      case SonusMotif.lightTrail:
        final glow = allowGlow
            ? (Paint()
                ..color = main.withValues(alpha: opacity * 0.4)
                ..strokeWidth = h * 0.5
                ..strokeCap = StrokeCap.round
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3))
            : null;
        for (var i = 0; i < 3; i++) {
          final y = h * (0.2 + i * 0.3);
          final end = w * (1 - i * 0.22);
          final line = stroke(
            (i.isEven ? main : accent).withValues(
              alpha: opacity * (1 - i * 0.25),
            ),
            h * 0.14,
          );
          if (glow != null && i == 0) {
            canvas.drawLine(Offset(0, y), Offset(end, y), glow);
          }
          canvas.drawLine(Offset(0, y), Offset(end, y), line);
        }
      case SonusMotif.chrome:
        final rect = Rect.fromLTWH(0, h * 0.2, w, h * 0.6);
        final paint = Paint();
        if (allowGradients) {
          paint.shader = ui.Gradient.linear(
            rect.topLeft,
            rect.topRight,
            [main, Colors.white.withValues(alpha: opacity * 0.85), accent],
            const [0, 0.45, 1],
          );
        } else {
          paint.color = main;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h)),
          paint,
        );
      case SonusMotif.neon:
        final rect = RRect.fromLTRBR(1, 1, w - 1, h - 1, Radius.circular(h));
        if (allowGlow) {
          canvas.drawRRect(
            rect,
            stroke(main.withValues(alpha: opacity * 0.5), 4)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
        canvas.drawRRect(rect, stroke(main, 1.6));
      case SonusMotif.haze:
        final rect = Rect.fromLTWH(0, 0, w, h);
        final paint = Paint();
        if (allowGradients) {
          paint.shader = ui.Gradient.radial(
            rect.centerLeft.translate(w * 0.3, 0),
            w * 0.6,
            [accent, accent.withValues(alpha: 0)],
          );
        } else {
          paint.color = accent.withValues(alpha: opacity * 0.6);
        }
        canvas.drawOval(rect, paint);
      case SonusMotif.geometric:
        canvas.drawRect(Rect.fromLTWH(0, 0, h, h), fill(main));
        canvas.drawRect(
          Rect.fromLTWH(h * 1.5, h * 0.35, w - h * 1.5, h * 0.3),
          fill(main),
        );
      case SonusMotif.editorial:
        canvas.drawLine(
          Offset(0, h * 0.3),
          Offset(w, h * 0.3),
          stroke(main, 2),
        );
        canvas.drawLine(
          Offset(0, h * 0.75),
          Offset(w * 0.6, h * 0.75),
          stroke(main, 1),
        );
      case SonusMotif.organic:
        final path = Path()..moveTo(0, h * 0.6);
        for (var x = 0.0; x <= w; x += 2) {
          path.lineTo(x, h * 0.5 + math.sin(x / w * math.pi * 2) * h * 0.3);
        }
        canvas.drawPath(path, stroke(main, h * 0.24));
    }
  }

  @override
  bool shouldRepaint(SonusMotifPainter oldDelegate) {
    return oldDelegate.motif != motif ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.opacity != opacity ||
        oldDelegate.allowGlow != allowGlow ||
        oldDelegate.allowGradients != allowGradients;
  }
}

/// A very faint surface texture behind hero and header areas. Drawn only
/// when the theme has one and decoration is Standard or Expressive.
class SonusSurfaceTexture extends StatelessWidget {
  const SonusSurfaceTexture({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    if (!tokens.decoration.showTexture) {
      return const SizedBox.shrink();
    }

    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey<String>('sonus-surface-texture'),
            painter: SonusTexturePainter(
              color: tokens.colors.textPrimary.withValues(
                alpha: tokens.decoration.textureOpacity,
              ),
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Deterministic speckle; the same size always paints the same pattern.
class SonusTexturePainter extends CustomPainter {
  const SonusTexturePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(48);
    final count = math.min(600, (size.width * size.height / 400).round());
    final points = [
      for (var i = 0; i < count; i++)
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
    ];

    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(SonusTexturePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A major section heading with the theme's motif underneath.
class SonusSectionHeading extends StatelessWidget {
  const SonusSectionHeading({
    super.key,
    required this.title,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.text.sectionHeading.copyWith(
                color: tokens.colors.textPrimary,
              ),
            ),
          ),
          if (tokens.decoration.showMarks) ...[
            SizedBox(height: tokens.metrics.spaceXs),
            const SonusMotifMark(),
          ],
        ],
      ),
    );
  }
}

/// The fallback shown where artwork is missing or fails to load.
class SonusArtworkPlaceholder extends StatelessWidget {
  const SonusArtworkPlaceholder({
    super.key,
    this.icon = Icons.music_note_rounded,
    this.iconSize,
  });

  final IconData icon;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ColoredBox(
      color: colors.artworkPlaceholder,
      child: Center(
        child: Icon(icon, size: iconSize, color: colors.onArtworkPlaceholder),
      ),
    );
  }
}
