import '../models/lyric_line.dart';

abstract final class LrcParser {
  static final RegExp _timestampPattern = RegExp(
    r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]',
  );

  static List<LyricLine> parse(String source) {
    final lines = <LyricLine>[];

    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final matches = _timestampPattern.allMatches(rawLine).toList();

      if (matches.isEmpty) {
        continue;
      }

      final text = rawLine.replaceAll(_timestampPattern, '').trim();

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3);

        if (seconds >= 60) {
          continue;
        }

        lines.add(
          LyricLine(
            timestamp: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: _fractionToMilliseconds(fraction),
            ),
            text: text,
          ),
        );
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return List<LyricLine>.unmodifiable(lines);
  }

  static int _fractionToMilliseconds(String? fraction) {
    if (fraction == null || fraction.isEmpty) {
      return 0;
    }

    return switch (fraction.length) {
      1 => int.parse(fraction) * 100,
      2 => int.parse(fraction) * 10,
      _ => int.parse(fraction.substring(0, 3)),
    };
  }
}
