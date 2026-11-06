// A golden comparator for the protected visual baselines that absorbs tiny
// rasterisation differences (anti-aliasing, GPU/driver rounding) but fails
// on real changes.
//
// A pixel counts as changed when any channel differs by more than
// [channelTolerance] (out of 255). The comparison passes only when the
// images have the same size and at most [maxChangedShare] of the pixels
// changed. A layout shift, a colour change, a missing icon or a resized
// picture changes far more than that.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(
    super.testFile, {
    this.channelTolerance = 8,
    this.maxChangedShare = 0.002,
  });

  /// Largest per-channel difference (0-255) that still counts as equal.
  final int channelTolerance;

  /// Largest share of changed pixels (0.002 = 0.2%) that still passes.
  final double maxChangedShare;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = Uint8List.fromList(await getGoldenBytes(golden));
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      goldenBytes,
    );
    if (result.passed) {
      result.dispose();
      return true;
    }
    final diff = await measureDifference(imageBytes, goldenBytes);
    if (diff.sameSize && diff.changedShare <= maxChangedShare) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(
      '$error\nTolerant comparison: ${diff.describe()} '
      '(allowed: ${(maxChangedShare * 100).toStringAsFixed(2)}% of pixels '
      'differing by more than $channelTolerance/255).',
    );
  }

  /// The share of pixels that differ by more than [channelTolerance].
  Future<GoldenDifference> measureDifference(
    Uint8List actual,
    Uint8List expected,
  ) async {
    final a = await _decode(actual);
    final b = await _decode(expected);
    try {
      if (a.width != b.width || a.height != b.height) {
        return GoldenDifference(
          sameSize: false,
          changedPixels: a.width * a.height,
          totalPixels: a.width * a.height,
          largestChannelDifference: 255,
          description:
              'size ${a.width}x${a.height} vs golden ${b.width}x${b.height}',
        );
      }
      final pa = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final pb = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var changed = 0;
      var largest = 0;
      for (var i = 0; i < pa.lengthInBytes; i += 4) {
        var pixelChanged = false;
        for (var c = 0; c < 4; c++) {
          final d = (pa.getUint8(i + c) - pb.getUint8(i + c)).abs();
          if (d > largest) largest = d;
          if (d > channelTolerance) pixelChanged = true;
        }
        if (pixelChanged) changed++;
      }
      return GoldenDifference(
        sameSize: true,
        changedPixels: changed,
        totalPixels: a.width * a.height,
        largestChannelDifference: largest,
      );
    } finally {
      a.dispose();
      b.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}

@immutable
class GoldenDifference {
  const GoldenDifference({
    required this.sameSize,
    required this.changedPixels,
    required this.totalPixels,
    required this.largestChannelDifference,
    this.description,
  });

  final bool sameSize;
  final int changedPixels;
  final int totalPixels;
  final int largestChannelDifference;
  final String? description;

  double get changedShare => totalPixels == 0 ? 0 : changedPixels / totalPixels;

  String describe() =>
      description ??
      '$changedPixels of $totalPixels pixels changed '
          '(${(changedShare * 100).toStringAsFixed(3)}%), largest channel '
          'difference $largestChannelDifference';
}
