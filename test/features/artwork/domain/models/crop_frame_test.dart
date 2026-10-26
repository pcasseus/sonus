import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_crop.dart';
import 'package:sonus_next/features/artwork/domain/models/crop_frame.dart';

void main() {
  test('a square frame on a landscape photo uses its full height', () {
    final frame = CropFrame.centered(
      imageWidth: 2000,
      imageHeight: 1000,
      aspectRatio: 1,
    );

    expect(frame.width, 1000);
    expect(frame.height, 1000);
    expect(frame.toRect(), CropRect(left: 0.25, top: 0, width: 0.5, height: 1));
  });

  test('a wide banner frame on a portrait photo uses its full width', () {
    final frame = CropFrame.centered(
      imageWidth: 900,
      imageHeight: 1600,
      aspectRatio: 4 / 3,
    );

    expect(frame.width, 900);
    expect(frame.height, closeTo(675, 1e-9));
  });

  test(
    'panning moves the frame against the drag and never leaves the image',
    () {
      var frame = CropFrame.centered(
        imageWidth: 2000,
        imageHeight: 1000,
        aspectRatio: 1,
      );

      // Dragging the image right shows more of its left side.
      frame = frame.panBy(100, 0, viewportWidth: 500);
      expect(frame.centerX, 1000 - 100 * (1000 / 500));

      frame = frame.panBy(100000, 100000, viewportWidth: 500);
      expect(frame.left, 0);
      expect(frame.top, 0);

      frame = frame.panBy(-100000, -100000, viewportWidth: 500);
      expect(frame.left + frame.width, 2000);
      expect(frame.top + frame.height, 1000);
    },
  );

  test('zoom is limited to 1x and the maximum', () {
    final frame = CropFrame.centered(
      imageWidth: 1000,
      imageHeight: 1000,
      aspectRatio: 1,
    );

    expect(frame.zoomTo(0.2).zoom, 1);
    expect(frame.zoomTo(100).zoom, CropFrame.maxZoom);
    expect(frame.zoomTo(double.nan).zoom, 1);
  });

  test('zooming around a point keeps that point under the finger', () {
    final frame = CropFrame.centered(
      imageWidth: 1000,
      imageHeight: 1000,
      aspectRatio: 1,
    );

    final zoomed = frame.zoomTo(2, focalX: 0.25, focalY: 0.25);
    // The image point at a quarter of the viewport stays at a quarter.
    expect(zoomed.left + 0.25 * zoomed.width, closeTo(250, 1e-9));
    expect(zoomed.top + 0.25 * zoomed.height, closeTo(250, 1e-9));
  });

  test('a saved rectangle reopens at the same place and zoom', () {
    final original = CropFrame.centered(
      imageWidth: 3000,
      imageHeight: 2000,
      aspectRatio: 1,
    ).zoomTo(2.5).panBy(-120, 40, viewportWidth: 400);

    final reopened = CropFrame.fromRect(
      imageWidth: 3000,
      imageHeight: 2000,
      aspectRatio: 1,
      rect: original.toRect(),
    );

    expect(reopened.zoom, closeTo(original.zoom, 1e-9));
    expect(reopened.centerX, closeTo(original.centerX, 1e-6));
    expect(reopened.centerY, closeTo(original.centerY, 1e-6));
  });

  test('nudges move by a fraction of the frame', () {
    final frame = CropFrame.centered(
      imageWidth: 2000,
      imageHeight: 1000,
      aspectRatio: 1,
    );

    expect(frame.nudge(0.1, 0).centerX, 1000 + 100);
  });

  test('invalid images are refused', () {
    expect(
      () => CropFrame.centered(imageWidth: 0, imageHeight: 10, aspectRatio: 1),
      throwsArgumentError,
    );
  });

  group('CropRect', () {
    test('must lie inside the image', () {
      expect(
        () => CropRect(left: 0.5, top: 0, width: 0.6, height: 1),
        throwsArgumentError,
      );
      expect(
        () => CropRect(left: 0, top: 0, width: 0, height: 1),
        throwsArgumentError,
      );
      expect(
        () => CropRect(left: double.nan, top: 0, width: 1, height: 1),
        throwsArgumentError,
      );
    });

    test('tiny rounding overshoot is clamped, not refused', () {
      final rect = CropRect(left: 0.5, top: 0, width: 0.5000000001, height: 1);
      expect(rect.left + rect.width, lessThanOrEqualTo(1.0));
    });
  });
}
