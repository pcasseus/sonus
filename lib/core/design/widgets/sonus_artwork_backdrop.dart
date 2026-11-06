import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// A full-bleed background drawn from artwork (UI redesign D13): a tiny,
/// heavily blurred copy of the image under a gradient from [top] to
/// [bottom]. It is the "pre-blurred backdrop" glass panels sit on, so the
/// panels themselves need no live blur.
///
/// The image is decoded at [decodeWidth] pixels and blurred once; a
/// [RepaintBoundary] keeps it from repainting with the content above.
/// Where gradients are not allowed (Decoration Off, High contrast, Low
/// effects), or there is no artwork, only the colours are drawn. Never
/// read by screen readers.
class SonusArtworkBackdrop extends StatelessWidget {
  const SonusArtworkBackdrop({
    super.key,
    required this.artworkPath,
    required this.top,
    required this.bottom,
    this.imageOpacity = 0.38,
  });

  final String? artworkPath;

  /// Background colour at the top, and at the bottom.
  final Color top;
  final Color bottom;

  /// How much of the blurred artwork shows through the colours.
  final double imageOpacity;

  /// The decode width: blurred this much, more pixels add nothing.
  static const int decodeWidth = 64;

  static const double blurSigma = 24;

  @override
  Widget build(BuildContext context) {
    final decoration = SonusTheme.of(context).decoration;
    final path = artworkPath?.trim();
    final showImage =
        decoration.allowGradients && path != null && path.isNotEmpty;

    final colours = DecoratedBox(
      key: const ValueKey<String>('sonus-artwork-backdrop-colours'),
      decoration: BoxDecoration(
        color: decoration.allowGradients ? null : top,
        gradient: decoration.allowGradients
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              )
            : null,
      ),
    );

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            colours,
            if (showImage)
              Opacity(
                opacity: imageOpacity,
                child: ImageFiltered(
                  key: const ValueKey<String>('sonus-artwork-backdrop-image'),
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                    tileMode: TileMode.decal,
                  ),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: decodeWidth,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            if (showImage)
              // Fades the image toward the bottom colour, so text below the
              // middle of the screen sits on the plain colours.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bottom.withValues(alpha: 0), bottom],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
