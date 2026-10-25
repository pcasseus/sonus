import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/entities/artwork_crop.dart';

/// Renders the cropped image a [CropRect] describes.
typedef ArtworkCropRender =
    Future<Uint8List> Function(
      Uint8List original,
      CropRect rect,
      ArtworkCropTarget target,
    );

/// Crops with Flutter's own image codecs (no extra dependency) and saves
/// a PNG at the target's output size, or smaller when the cropped part of
/// the original is smaller: images are never enlarged.
abstract final class ArtworkCropRenderer {
  /// Very large photos are decoded at most this wide or tall, which bounds
  /// memory while staying sharper than any output size.
  static const int maxDecodeEdge = 4096;

  static Future<Uint8List> render(
    Uint8List original,
    CropRect rect,
    ArtworkCropTarget target,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(original);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      maxDecodeEdge / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );

    ui.Image? image;
    ui.Image? output;

    try {
      image = (await codec.getNextFrame()).image;

      final source = ui.Rect.fromLTWH(
        rect.left * image.width,
        rect.top * image.height,
        rect.width * image.width,
        rect.height * image.height,
      );
      final width = math.max(
        1,
        math.min(target.outputWidth, source.width.round()),
      );
      final height = math.max(1, (width / target.aspectRatio).round());

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        source,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      picture.dispose();

      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);

      if (bytes == null) {
        throw StateError('The cropped image could not be encoded.');
      }

      return bytes.buffer.asUint8List();
    } finally {
      image?.dispose();
      output?.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
