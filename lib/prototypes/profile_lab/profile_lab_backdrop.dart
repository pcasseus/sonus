// Artist Profile Lab: the page's environment, fixed behind the content.
//
// PROTOTYPE ONLY (see profile_lab_models.dart).
//
// Layers, back to front:
// 1. the ground colour;
// 2. the artwork itself, decoded tiny, blurred and tone-mapped: its
//    lightness is compressed into a band that keeps text readable while its
//    own colours and shapes stay (a near-white cover becomes a soft silver
//    field, not a white page);
// 3. light: two pools in the artwork's hues, placed where they stay visible
//    after scrolling, soft wisps, and a vignette toward the deep tone.
// Nothing here is read by screen readers, and none of it repaints with the
// content (one RepaintBoundary, no animation).
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'profile_lab_atmosphere.dart';

class LabBackdrop extends StatelessWidget {
  const LabBackdrop({
    super.key,
    required this.artworkPath,
    required this.atmosphere,
    this.layers = LabLayers.all,
  });

  final String? artworkPath;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  /// The artwork is decoded this wide: blurred this much, more pixels add
  /// nothing, and the decode stays a few kilobytes.
  static const int decodeWidth = 40;

  /// Blurred well past recognisable shapes (a face or a silhouette): the
  /// artwork's colour and light stay, its outlines do not.
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
    final a = atmosphere;
    final path = artworkPath?.trim();
    final showImage =
        a.effects && layers.backdropImage && path != null && path.isNotEmpty;

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              key: const ValueKey<String>('lab-backdrop-ground'),
              color: a.ground,
            ),
            if (showImage)
              // The image fills the upper two thirds and fades into the
              // ground below, so the lower page is lit, not patterned.
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
                  key: const ValueKey<String>('lab-backdrop-image'),
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
            if (a.effects && layers.lights)
              CustomPaint(
                key: const ValueKey<String>('lab-backdrop-lights'),
                painter: LabLightPainter(a),
              ),
          ],
        ),
      ),
    );
  }
}

/// Light pools, wisps and the vignette, in fractions of the page size so
/// every phone gets the same composition.
class LabLightPainter extends CustomPainter {
  LabLightPainter(this.atmosphere);

  final LabAtmosphere atmosphere;

  @override
  void paint(Canvas canvas, Size size) {
    final a = atmosphere;
    final w = size.width, h = size.height;
    final strength = a.neutral ? 0.75 : 1.0;

    void pool(Offset centre, double radius, Color colour, double alpha) {
      final rect = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: alpha * strength),
              colour.withValues(alpha: alpha * strength * 0.35),
              colour.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }

    // Behind the identity block and the controls (top right), across the
    // middle of the screen (left), and low on the right: each stays in
    // view at every scroll position because the backdrop does not scroll.
    pool(Offset(w * 0.92, h * 0.40), w * 0.80, a.light, 0.30);
    pool(Offset(w * 0.02, h * 0.66), w * 0.78, a.lightSecondary, 0.24);
    pool(Offset(w * 0.78, h * 1.02), w * 0.70, a.light, 0.20);

    // Wisps: wide, soft strokes of light, like haze catching the light.
    final wisp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    void stroke(List<Offset> p, double width, Color colour, double alpha) {
      final path = Path()
        ..moveTo(p[0].dx * w, p[0].dy * h)
        ..cubicTo(
          p[1].dx * w,
          p[1].dy * h,
          p[2].dx * w,
          p[2].dy * h,
          p[3].dx * w,
          p[3].dy * h,
        );
      canvas.drawPath(
        path,
        wisp
          ..strokeWidth = width
          ..color = colour.withValues(alpha: alpha * strength),
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
      a.light,
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
      a.lightSecondary,
      0.09,
    );
    stroke(
      const [
        Offset(0.55, 0.20),
        Offset(0.80, 0.30),
        Offset(0.95, 0.10),
        Offset(1.2, 0.26),
      ],
      w * 0.07,
      a.light,
      0.08,
    );

    // Vignette: the corners fall to the deep tone; the centre is untouched.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.05,
          colors: [
            a.groundDeep.withValues(alpha: 0),
            a.groundDeep.withValues(alpha: 0),
            a.groundDeep.withValues(alpha: 0.72),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(LabLightPainter oldDelegate) =>
      oldDelegate.atmosphere != atmosphere;
}
