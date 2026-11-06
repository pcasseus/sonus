import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The artwork itself as a page's environment (Artist Profile Lab method,
/// approved 2026-11-06): decoded tiny, blurred well past recognisable
/// shapes and tone-mapped, so its colour and light fill the page while text
/// keeps its readable ground. A near-white cover becomes a soft silver
/// field, never a white page.
///
/// It draws only imagery, soft wisps of light and a vignette; the page's
/// own ground and light pools stay with the caller (for example
/// SonusProfileBackdrop). Nothing here is read by screen readers, and none
/// of it repaints with the content above it. Draws nothing when [enabled]
/// is false (Decoration Off, High contrast, Low effects).
class SonusArtworkEnvironment extends StatelessWidget {
  const SonusArtworkEnvironment({
    super.key,
    required this.artworkPath,
    required this.light,
    required this.deep,
    required this.enabled,
  });

  final String? artworkPath;

  /// The colour of the wisps (the page's light).
  final Color light;

  /// The tone the corners fall to.
  final Color deep;
  final bool enabled;

  /// Decoded this wide: blurred this much, more pixels add nothing.
  static const int decodeWidth = 40;
  static const double blurSigma = 46;

  /// Lightness compression of the artwork (see [toneMap]).
  static const double keepChroma = 0.66;
  static const double lightnessSlope = 0.27;
  static const double lift = 0.035;

  /// Maps each channel to `keepChroma * c + (slope - keepChroma) * L + lift`
  /// (L the pixel's luma): lightness is compressed to [lift, lift + slope]
  /// while the colour's own difference from grey is kept at [keepChroma].
  static ColorFilter toneMap() {
    const a = keepChroma;
    const b = lightnessSlope - keepChroma;
    const c = lift * 255;
    const r = 0.2126 * b, g = 0.7152 * b, bl = 0.0722 * b;
    return const ColorFilter.matrix(<double>[
      a + r, g, bl, 0, c, //
      r, a + g, bl, 0, c, //
      r, g, a + bl, 0, c, //
      0, 0, 0, 1, 0, //
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final path = artworkPath?.trim();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null && path.isNotEmpty)
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xB3FFFFFF),
                    Color(0x40FFFFFF),
                  ],
                  stops: [0, 0.55, 1],
                ).createShader(rect),
                child: ColorFiltered(
                  key: const ValueKey<String>(
                    'sonus-artwork-environment-image',
                  ),
                  colorFilter: toneMap(),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: blurSigma,
                      sigmaY: blurSigma,
                      tileMode: TileMode.mirror,
                    ),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth: decodeWidth,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            CustomPaint(
              key: const ValueKey<String>('sonus-artwork-environment-light'),
              painter: _WispsPainter(light: light, deep: deep),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft wisps of light and a vignette, in fractions of the page size.
class _WispsPainter extends CustomPainter {
  _WispsPainter({required this.light, required this.deep});

  final Color light;
  final Color deep;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final wisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    void stroke(List<Offset> p, double width, double alpha) {
      canvas.drawPath(
        Path()
          ..moveTo(p[0].dx * w, p[0].dy * h)
          ..cubicTo(
            p[1].dx * w,
            p[1].dy * h,
            p[2].dx * w,
            p[2].dy * h,
            p[3].dx * w,
            p[3].dy * h,
          ),
        wisp
          ..strokeWidth = width
          ..color = light.withValues(alpha: alpha),
      );
    }

    stroke(
      const [
        Offset(-0.1, 0.52),
        Offset(0.30, 0.40),
        Offset(0.62, 0.62),
        Offset(1.1, 0.48),
      ],
      w * 0.10,
      0.10,
    );
    stroke(
      const [
        Offset(-0.1, 0.80),
        Offset(0.25, 0.92),
        Offset(0.70, 0.70),
        Offset(1.1, 0.86),
      ],
      w * 0.14,
      0.08,
    );
    stroke(
      const [
        Offset(0.55, 0.20),
        Offset(0.80, 0.30),
        Offset(0.95, 0.10),
        Offset(1.2, 0.26),
      ],
      w * 0.07,
      0.08,
    );

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.05,
          colors: [
            deep.withValues(alpha: 0),
            deep.withValues(alpha: 0),
            deep.withValues(alpha: 0.6),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(_WispsPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.deep != deep;
}
