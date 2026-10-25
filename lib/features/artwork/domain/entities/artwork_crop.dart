/// What a crop frames, and the shape it must have.
enum ArtworkCropTarget {
  /// An album edition's square cover.
  albumEdition(aspectRatio: 1, outputWidth: 1200),

  /// The wide photograph across the top of an Artist Profile.
  artistBanner(aspectRatio: 4 / 3, outputWidth: 1600),

  /// The artist's square identity photo, shown in a circle.
  artistPortrait(aspectRatio: 1, outputWidth: 1000);

  const ArtworkCropTarget({
    required this.aspectRatio,
    required this.outputWidth,
  });

  /// Width divided by height.
  final double aspectRatio;

  /// Width of the saved image, in pixels; never larger than the original.
  final int outputWidth;

  int get outputHeight => (outputWidth / aspectRatio).round();
}

/// A rectangle inside an image, as fractions of its width and height.
class CropRect {
  const CropRect._(this.left, this.top, this.width, this.height);

  /// Validates the rectangle: inside the image and not empty. A tiny
  /// rounding overshoot is clamped away.
  factory CropRect({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    const tolerance = 1e-6;
    final values = [left, top, width, height];

    if (values.any((value) => value.isNaN || value.isInfinite)) {
      throw ArgumentError('Crop values must be finite.');
    }

    if (width <= 0 ||
        height <= 0 ||
        left < -tolerance ||
        top < -tolerance ||
        left + width > 1 + tolerance ||
        top + height > 1 + tolerance) {
      throw ArgumentError(
        'Crop rectangle must lie inside the image: '
        '($left, $top, $width, $height).',
      );
    }

    final l = left.clamp(0.0, 1.0);
    final t = top.clamp(0.0, 1.0);
    return CropRect._(
      l,
      t,
      width.clamp(tolerance, 1.0 - l),
      height.clamp(tolerance, 1.0 - t),
    );
  }

  /// The whole image.
  static const CropRect full = CropRect._(0, 0, 1, 1);

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      (other.left - left).abs() < 1e-9 &&
      (other.top - top).abs() < 1e-9 &&
      (other.width - width).abs() < 1e-9 &&
      (other.height - height).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(
    (left * 1e6).round(),
    (top * 1e6).round(),
    (width * 1e6).round(),
    (height * 1e6).round(),
  );

  @override
  String toString() => 'CropRect($left, $top, $width, $height)';
}

/// How one cover or artist photo was cropped from its original.
class ArtworkCrop {
  const ArtworkCrop({
    required this.target,
    required this.targetId,
    required this.sourceArtworkId,
    required this.outputArtworkId,
    required this.rect,
    required this.createdAt,
    required this.updatedAt,
  });

  final ArtworkCropTarget target;

  /// The album edition or artist ID.
  final String targetId;

  /// The untouched original, kept so the crop can move or be reset.
  final String sourceArtworkId;

  /// The cropped image assigned to the target.
  final String outputArtworkId;

  final CropRect rect;
  final DateTime createdAt;
  final DateTime updatedAt;
}
