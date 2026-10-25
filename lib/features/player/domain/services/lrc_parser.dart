import '../models/lyric_line.dart';

abstract final class LrcParser {
  static final RegExp _timestampPattern = RegExp(
    r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]',
  );

  /// `[offset:±ms]`: a positive offset shows every line earlier.
  static final RegExp _offsetPattern = RegExp(
    r'^\s*\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );

  static List<LyricLine> parse(String source) {
    final lines = <LyricLine>[];
    var offset = Duration.zero;
    // Lines produced by the most recent timed line.
    List<int> continuing = const [];

    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final offsetMatch = _offsetPattern.firstMatch(rawLine);

      if (offsetMatch != null) {
        offset = Duration(milliseconds: int.parse(offsetMatch.group(1)!));
        continue;
      }

      final matches = _timestampPattern.allMatches(rawLine).toList();

      if (matches.isEmpty) {
        // Some files wrap a long lyric onto untimed lines: they continue
        // the timed line above. Blank lines, tags and other bracketed text
        // are not lyrics, and text before the first timestamp is a header.
        final continuation = rawLine.trim();

        if (continuation.isNotEmpty && !continuation.startsWith('[')) {
          for (final index in continuing) {
            lines[index] = LyricLine(
              timestamp: lines[index].timestamp,
              text: '${lines[index].text}\n$continuation',
            );
          }
        } else {
          // A blank line or a tag ends the lyric above.
          continuing = const [];
        }

        continue;
      }

      final text = rawLine.replaceAll(_timestampPattern, '').trim();
      final added = <int>[];

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3);

        if (seconds >= 60) {
          continue;
        }

        added.add(lines.length);
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

      continuing = added;
    }

    // List.sort is not stable; lines sharing a timestamp (duets, repeated
    // choruses) must keep the order they have in the file.
    final ordered =
        [for (var i = 0; i < lines.length; i++) (index: i, line: lines[i])]
          ..sort((a, b) {
            final byTime = a.line.timestamp.compareTo(b.line.timestamp);
            return byTime != 0 ? byTime : a.index.compareTo(b.index);
          });

    return List<LyricLine>.unmodifiable([
      for (final entry in ordered) _shifted(entry.line, offset),
    ]);
  }

  static LyricLine _shifted(LyricLine line, Duration offset) {
    if (offset == Duration.zero) {
      return line;
    }

    final shifted = line.timestamp - offset;

    return LyricLine(
      timestamp: shifted < Duration.zero ? Duration.zero : shifted,
      text: line.text,
    );
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
