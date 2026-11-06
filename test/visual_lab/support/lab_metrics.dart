// Measurements on rendered pixels for the Artist Profile Lab.
//
// These measure what hue checks cannot: lightness structure, how much of
// the page is imagery, whether glass reads as its own material, and the
// contrast of every text against the pixels actually under it.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lab_harness.dart';

double _linear(int c) {
  final v = c / 255;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// Relative luminance (WCAG) of an sRGB pixel.
double luminance((int, int, int) p) =>
    0.2126 * _linear(p.$1) + 0.7152 * _linear(p.$2) + 0.0722 * _linear(p.$3);

double _f(double t) =>
    t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

/// CIE L*a*b* (D65) of an sRGB pixel.
(double, double, double) lab((int, int, int) p) {
  final r = _linear(p.$1), g = _linear(p.$2), b = _linear(p.$3);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  final fx = _f(x), fy = _f(y), fz = _f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double lStar((int, int, int) p) => lab(p).$1;

double percentile(List<double> values, double p) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

/// Pixels of [image] inside [logical] (logical pixels), every [step].
Iterable<(int, int, int)> pixelsIn(
  LabPixels image,
  Rect logical, {
  int step = 2,
}) sync* {
  final r = Rect.fromLTRB(
    (logical.left * image.scale).clamp(0, image.width - 1),
    (logical.top * image.scale).clamp(0, image.height - 1),
    (logical.right * image.scale).clamp(0, image.width.toDouble()),
    (logical.bottom * image.scale).clamp(0, image.height.toDouble()),
  );
  for (var y = r.top.floor(); y < r.bottom.floor(); y += step) {
    for (var x = r.left.floor(); x < r.right.floor(); x += step) {
      yield image.at(x, y);
    }
  }
}

/// The lightness structure of a region.
class LightnessRange {
  LightnessRange(List<double> l, List<double> y)
    : p5 = percentile(l, 0.05),
      p50 = percentile(l, 0.5),
      p95 = percentile(l, 0.95),
      luminanceRatio =
          (percentile(y, 0.95) + 0.05) / (percentile(y, 0.05) + 0.05);

  factory LightnessRange.of(LabPixels image, Rect region) {
    final l = <double>[], y = <double>[];
    for (final p in pixelsIn(image, region)) {
      l.add(lStar(p));
      y.add(luminance(p));
    }
    return LightnessRange(l, y);
  }

  final double p5;
  final double p50;
  final double p95;

  /// Brightest to darkest (5th to 95th percentile), as a contrast ratio.
  final double luminanceRatio;

  double get spread => p95 - p5;

  Map<String, Object> toJson() => {
    'L*_p5': _r(p5),
    'L*_p50': _r(p50),
    'L*_p95': _r(p95),
    'L*_spread': _r(spread),
    'luminance_ratio': _r(luminanceRatio),
  };
}

double _r(double v) => (v * 100).round() / 100;

/// Share of [region] whose colour comes from imagery: pixels that differ by
/// more than [threshold] (CIE76 ΔE) from the same render without imagery.
double imageryCoverage(
  LabPixels withImagery,
  LabPixels withoutImagery,
  Rect region, {
  double threshold = 5,
}) {
  final a = pixelsIn(withImagery, region).toList();
  final b = pixelsIn(withoutImagery, region).toList();
  var hits = 0;
  for (var i = 0; i < a.length; i++) {
    final x = lab(a[i]), y = lab(b[i]);
    final d = math.sqrt(
      math.pow(x.$1 - y.$1, 2) +
          math.pow(x.$2 - y.$2, 2) +
          math.pow(x.$3 - y.$3, 2),
    );
    if (d > threshold) hits++;
  }
  return a.isEmpty ? 0 : hits / a.length;
}

/// Mean CIE76 ΔE between a region of two renders (how much a layer adds).
double meanDeltaE(LabPixels a, LabPixels b, Rect region) {
  final pa = pixelsIn(a, region).toList();
  final pb = pixelsIn(b, region).toList();
  var sum = 0.0;
  for (var i = 0; i < pa.length; i++) {
    final x = lab(pa[i]), y = lab(pb[i]);
    sum += math.sqrt(
      math.pow(x.$1 - y.$1, 2) +
          math.pow(x.$2 - y.$2, 2) +
          math.pow(x.$3 - y.$3, 2),
    );
  }
  return pa.isEmpty ? 0 : sum / pa.length;
}

/// How much a glass plate changes the backdrop directly behind it: median
/// L* inside the plate (away from its edge) with the plate drawn, against
/// the same pixels rendered without glass. Comparing with a ring outside
/// the plate instead mixes in uneven light around it.
class GlassSeparation {
  GlassSeparation(this.inside, this.outside);

  factory GlassSeparation.of(
    LabPixels withGlass,
    LabPixels withoutGlass,
    Rect plate,
  ) {
    // A strip of bare plate: inside its right edge, past row dividers and
    // content (icons are transparent in an ink-off render), clear of the
    // rim. Pictures and placeholders are drawn the same either way and
    // would hide the plate's own effect.
    final strip = Rect.fromLTRB(
      plate.right - 14,
      plate.top + 16,
      plate.right - 6,
      plate.bottom - 16,
    );
    double median(LabPixels p) =>
        percentile(pixelsIn(p, strip, step: 1).map(lStar).toList(), 0.5);
    return GlassSeparation(median(withGlass), median(withoutGlass));
  }

  final double inside;

  /// The same region without the plate.
  final double outside;
  double get delta => (inside - outside).abs();

  Map<String, Object> toJson() => {
    'with_glass_L*': _r(inside),
    'without_glass_L*': _r(outside),
    'delta_L*': _r(delta),
  };
}

double _ratio(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// One text's contrast on the ground actually under it.
class TextContrast {
  TextContrast(
    this.text,
    this.rect,
    this.worst,
    this.median,
    this.large, {
    this.icon = false,
  });

  /// An icon glyph (3:1, as for large text and other graphics).
  final bool icon;

  final String text;
  final Rect rect;

  /// 5th-percentile contrast across the pixels under the text (its worst
  /// ground), and the median.
  final double worst;
  final double median;

  /// WCAG large text (>= 24 px, or >= 18.66 px bold): 3:1 suffices.
  final bool large;

  double get required => large ? 3.0 : 4.5;
  bool get passes => worst >= required;

  Map<String, Object> toJson() => {
    'text': icon ? 'icon U+${text.runes.first.toRadixString(16)}' : text,
    'worst': _r(worst),
    'median': _r(median),
    'required': required,
  };
}

/// A text as drawn: where it is, its colour and whether it is large.
class TextSample {
  TextSample(this.text, this.rect, this.colour, this.large, this.icon);

  final String text;
  final Rect rect;
  final Color colour;
  final bool large;

  /// A Material icon glyph: a graphic, for which WCAG asks 3:1.
  final bool icon;
}

/// Every fully shown text on the page as drawn now (with ink). Texts under
/// the toolbar or the mini-player, which cover them, are skipped, except
/// their own; so are texts partly off screen.
List<TextSample> collectTexts(WidgetTester tester) =>
    collectTextsIn(tester, 'lab-page');

/// [collectTexts] for any page, found by its key.
List<TextSample> collectTextsIn(WidgetTester tester, String pageKey) {
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  Rect? rectOf(String key) {
    final f = find.byKey(ValueKey<String>(key));
    return f.evaluate().isEmpty ? null : tester.getRect(f);
  }

  Set<RenderObject> inside(String key) {
    final f = find.byKey(ValueKey<String>(key));
    if (f.evaluate().isEmpty) return {};
    return tester
        .renderObjectList(
          find.descendant(of: f, matching: find.byType(RichText)),
        )
        .toSet();
  }

  final toolbar = rectOf('lab-toolbar');
  final mini = rectOf('lab-mini-player');
  final own = {...inside('lab-toolbar'), ...inside('lab-mini-player')};
  final samples = <TextSample>[];
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byKey(ValueKey<String>(pageKey)),
      matching: find.byType(RichText),
    ),
  )) {
    final text = paragraph.text.toPlainText().trim();
    final colour = paragraph.text.style?.color;
    if (text.isEmpty || colour == null || colour.a == 0) continue;
    // A disabled control (drawn translucent) is exempt from contrast
    // requirements (WCAG 1.4.3 / 1.4.11: inactive components).
    if (colour.a < 0.6) continue;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    if (rect.isEmpty ||
        !screen.contains(rect.topLeft) ||
        !screen.contains(rect.bottomRight - const Offset(1, 1))) {
      continue;
    }
    if (!own.contains(paragraph) &&
        ((toolbar != null && toolbar.overlaps(rect)) ||
            (mini != null && mini.overlaps(rect)))) {
      continue;
    }
    // A faded toolbar title is not shown: only fully shown text counts.
    if (_opacityOf(paragraph) < 0.99) continue;
    final style = paragraph.text.style!;
    final size = (style.fontSize ?? 14) * paragraph.textScaler.scale(1);
    final bold = (style.fontWeight?.value ?? 400) >= 700;
    samples.add(
      TextSample(
        text.length > 28 ? '${text.substring(0, 28)}…' : text,
        rect,
        colour,
        size >= 24 || (bold && size >= 18.66),
        style.fontFamily == 'MaterialIcons',
      ),
    );
  }
  return samples;
}

/// The contrast of each of [samples] against [inkless] (the same layout
/// with ink transparent): every pixel under the text, the text's colour
/// composited over it.
List<TextContrast> measureTexts(List<TextSample> samples, LabPixels inkless) {
  final results = <TextContrast>[];
  for (final s in samples) {
    final c = s.colour;
    final ratios = <double>[];
    for (final p in pixelsIn(inkless, s.rect, step: 1)) {
      final fg = (
        ((c.r * c.a + p.$1 / 255 * (1 - c.a)) * 255).round(),
        ((c.g * c.a + p.$2 / 255 * (1 - c.a)) * 255).round(),
        ((c.b * c.a + p.$3 / 255 * (1 - c.a)) * 255).round(),
      );
      ratios.add(_ratio(luminance(fg), luminance(p)));
    }
    if (ratios.isEmpty) continue;
    results.add(
      TextContrast(
        s.text,
        s.rect,
        percentile(ratios, 0.05),
        percentile(ratios, 0.5),
        s.large || s.icon,
        icon: s.icon,
      ),
    );
  }
  return results;
}

double _opacityOf(RenderObject object) {
  var opacity = 1.0;
  RenderObject? node = object.parent;
  while (node != null) {
    if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
    if (node is RenderOpacity) opacity *= node.opacity;
    node = node.parent;
  }
  return opacity;
}

/// The share of an icon's box its glyph covers: a real Material icon covers
/// well under half; the test font's square covers nearly all of it.
double glyphCoverage(LabPixels image, Rect box, (int, int, int) ground) {
  var hits = 0, total = 0;
  final g = luminance(ground);
  for (final p in pixelsIn(image, box, step: 1)) {
    total++;
    if ((luminance(p) - g).abs() > 0.2) hits++;
  }
  return total == 0 ? 0 : hits / total;
}

/// Every shown text, against the ground just above and below its box (thin
/// bands inside the line spacing, where no glyph ink falls): the brightest
/// 5% of those pixels is its worst ground. The production page has no
/// ink-off switch, so the ground is read beside the glyphs, not under them.
List<TextContrast> measureTextsBeside(
  List<TextSample> samples,
  LabPixels pixels,
) {
  final results = <TextContrast>[];
  for (final s in samples) {
    final c = s.colour;
    final textLum = luminance((
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    ));
    final r = s.rect;
    final ground = [
      for (final band in [
        Rect.fromLTRB(r.left, r.top - 2, r.right, r.top),
        Rect.fromLTRB(r.left, r.bottom, r.right, r.bottom + 2),
      ])
        for (final p in pixelsIn(pixels, band, step: 1)) luminance(p),
    ];
    if (ground.isEmpty) continue;
    double ratio(double g) {
      final fg = c.a * textLum + (1 - c.a) * g;
      final hi = fg > g ? fg : g, lo = fg > g ? g : fg;
      return (hi + 0.05) / (lo + 0.05);
    }

    results.add(
      TextContrast(
        s.icon ? 'icon U+${s.text.runes.first.toRadixString(16)}' : s.text,
        r,
        ratio(percentile(ground, 0.95)),
        ratio(percentile(ground, 0.5)),
        s.large || s.icon,
        icon: s.icon,
      ),
    );
  }
  return results;
}
