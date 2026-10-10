import 'dart:io';
import 'dart:ui' as ui;

class CoverArtImageValidationException implements Exception {
  const CoverArtImageValidationException(this.message);

  final String message;

  @override
  String toString() => 'CoverArtImageValidationException: $message';
}

class CoverArtImageValidator {
  const CoverArtImageValidator({this.maximumBytes = 10 * 1024 * 1024});

  final int maximumBytes;

  Future<void> validate(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw const CoverArtImageValidationException(
        'Artwork file does not exist.',
      );
    }

    final size = await file.length();

    if (size == 0 || size > maximumBytes) {
      throw const CoverArtImageValidationException(
        'Artwork file has an invalid size.',
      );
    }

    final bytes = await file.readAsBytes();
    ui.Codec? codec;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;

      if (image.width <= 0 || image.height <= 0) {
        throw const CoverArtImageValidationException(
          'Artwork has invalid dimensions.',
        );
      }
    } catch (_) {
      throw const CoverArtImageValidationException(
        'Artwork could not be decoded as an image.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
