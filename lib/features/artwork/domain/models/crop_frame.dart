import 'dart:math' as math;

import '../entities/artwork_crop.dart';

/// The visible part of an image in a crop editor with a fixed shape.
///
/// At zoom 1 the frame is the largest rectangle of [aspectRatio] that fits
/// the image; zooming in makes it smaller. The frame always stays inside
/// the image, so a crop never shows empty space. Immutable.
class CropFrame {
  CropFrame._({
    required this.imageWidth,
    required this.imageHeight,
    required this.aspectRatio,
    required this.zoom,
    required this.centerX,
    required this.centerY,
  });

  /// A frame centered on the image at zoom 1.
  factory CropFrame.centered({
    required double imageWidth,
    required double imageHeight,
    required double aspectRatio,
  }) {
    _checkSize(imageWidth, imageHeight, aspectRatio);
    return CropFrame._(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspectRatio: aspectRatio,
      zoom: 1,
      centerX: imageWidth / 2,
      centerY: imageHeight / 2,
    );
  }

  /// The frame for a saved [rect]. A rectangle of another shape (for
  /// example after the target's shape changed) keeps its center and the
  /// zoom of its width.
  factory CropFrame.fromRect({
    required double imageWidth,
    required double imageHeight,
    required double aspectRatio,
    required CropRect rect,
  }) {
    _checkSize(imageWidth, imageHeight, aspectRatio);
    final base = math.min(imageWidth, imageHeight * aspectRatio);
    final width = rect.width * imageWidth;
    return CropFrame._(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspectRatio: aspectRatio,
      zoom: 1,
      centerX: (rect.left + rect.width / 2) * imageWidth,
      centerY: (rect.top + rect.height / 2) * imageHeight,
    ).zoomTo(base / width);
  }

  static const double maxZoom = 6;

  final double imageWidth;
  final double imageHeight;
  final double aspectRatio;
  final double zoom;

  /// The frame's center, in image pixels.
  final double centerX;
  final double centerY;

  double get _baseWidth => math.min(imageWidth, imageHeight * aspectRatio);

  /// The frame's size, in image pixels.
  double get width => _baseWidth / zoom;
  double get height => width / aspectRatio;

  double get left => centerX - width / 2;
  double get top => centerY - height / 2;

  /// Moves the image by a drag of [dx], [dy] on a viewport [viewportWidth]
  /// wide: dragging right reveals more of the image's left side.
  CropFrame panBy(double dx, double dy, {required double viewportWidth}) {
    if (viewportWidth <= 0) return this;
    final scale = width / viewportWidth;
    return _copy(centerX: centerX - dx * scale, centerY: centerY - dy * scale);
  }

  /// Moves the frame by a fraction of its own size (keyboard and screen
  /// reader nudges).
  CropFrame nudge(double fractionX, double fractionY) => _copy(
    centerX: centerX + fractionX * width,
    centerY: centerY + fractionY * height,
  );

  /// Zooms to [value] (clamped to 1 to [maxZoom]). With a [focalX],
  /// [focalY] as fractions of the viewport, that point stays put.
  CropFrame zoomTo(double value, {double focalX = 0.5, double focalY = 0.5}) {
    final next = value.isNaN ? 1.0 : value.clamp(1.0, maxZoom).toDouble();
    final focusX = left + focalX * width;
    final focusY = top + focalY * height;
    final nextWidth = _baseWidth / next;
    final nextHeight = nextWidth / aspectRatio;
    return CropFrame._(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspectRatio: aspectRatio,
      zoom: next,
      centerX: focusX - (focalX - 0.5) * nextWidth,
      centerY: focusY - (focalY - 0.5) * nextHeight,
    )._clamped();
  }

  /// The frame as a saved rectangle.
  CropRect toRect() => CropRect(
    left: left / imageWidth,
    top: top / imageHeight,
    width: width / imageWidth,
    height: height / imageHeight,
  );

  CropFrame _copy({required double centerX, required double centerY}) =>
      CropFrame._(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspectRatio: aspectRatio,
        zoom: zoom,
        centerX: centerX,
        centerY: centerY,
      )._clamped();

  CropFrame _clamped() {
    final halfWidth = width / 2;
    final halfHeight = height / 2;
    return CropFrame._(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspectRatio: aspectRatio,
      zoom: zoom,
      centerX: centerX.clamp(halfWidth, imageWidth - halfWidth).toDouble(),
      centerY: centerY.clamp(halfHeight, imageHeight - halfHeight).toDouble(),
    );
  }

  static void _checkSize(double width, double height, double aspect) {
    if (!(width > 0) || !(height > 0) || !(aspect > 0)) {
      throw ArgumentError('Image size and shape must be positive.');
    }
  }
}
