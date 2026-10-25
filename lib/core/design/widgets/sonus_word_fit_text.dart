import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text that wraps between words, never inside one.
///
/// Titles still wrap normally; only when a single word is wider than the
/// available width (a long word at 320dp with 2x text) is the font reduced,
/// just enough for that word to fit, and never below [minScale] of the
/// style's size, so it stays readable. Text scaling still applies first,
/// and screen readers read the text unchanged.
class SonusWordFitText extends StatelessWidget {
  const SonusWordFitText(
    this.data, {
    super.key,
    required this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.minScale = 0.6,
    this.textKey,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  /// The smallest share of the style's font size a long word may use.
  final double minScale;

  /// Key of the inner [Text], for callers that look it up.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        final width = constraints.maxWidth;
        final words = data.split(RegExp(r'\s+'));

        var scale = 1.0;
        if (width.isFinite && width > 0 && words.isNotEmpty) {
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          var widest = 0.0;
          for (final word in words) {
            if (word.isEmpty) continue;
            final painter = TextPainter(
              text: TextSpan(text: word, style: base),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            widest = math.max(widest, painter.width);
            painter.dispose();
          }
          if (widest > width) {
            scale = math.max(minScale, width / widest * 0.98);
          }
        }

        final fontSize = base.fontSize;

        return Text(
          data,
          key: textKey,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign,
          style: scale == 1 || fontSize == null
              ? style
              : style?.copyWith(fontSize: fontSize * scale) ??
                    TextStyle(fontSize: fontSize * scale),
        );
      },
    );
  }
}
