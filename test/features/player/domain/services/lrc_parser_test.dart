import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/services/lrc_parser.dart';

void main() {
  test('parses and sorts timestamped lyric lines', () {
    const source = '''
[00:12.50]Second
[00:05.25]First
[01:02.125]Third
''';

    final lines = LrcParser.parse(source);

    expect(lines, hasLength(3));
    expect(lines[0].timestamp, const Duration(seconds: 5, milliseconds: 250));
    expect(lines[0].text, 'First');
    expect(lines[1].timestamp, const Duration(seconds: 12, milliseconds: 500));
    expect(lines[1].text, 'Second');
    expect(
      lines[2].timestamp,
      const Duration(minutes: 1, seconds: 2, milliseconds: 125),
    );
    expect(lines[2].text, 'Third');
  });

  test('supports multiple timestamps for one lyric line', () {
    const source = '[00:05.00][00:10.00]Repeated';

    final lines = LrcParser.parse(source);

    expect(lines, hasLength(2));
    expect(lines[0].timestamp, const Duration(seconds: 5));
    expect(lines[1].timestamp, const Duration(seconds: 10));
    expect(lines.every((line) => line.text == 'Repeated'), isTrue);
  });

  test('supports one two and three digit timestamp fractions', () {
    const source = '''
[00:01.1]Tenths
[00:02.12]Hundredths
[00:03.123]Milliseconds
''';

    final lines = LrcParser.parse(source);

    expect(lines[0].timestamp, const Duration(seconds: 1, milliseconds: 100));
    expect(lines[1].timestamp, const Duration(seconds: 2, milliseconds: 120));
    expect(lines[2].timestamp, const Duration(seconds: 3, milliseconds: 123));
  });

  test('ignores metadata and untimed text', () {
    const source = '''
[ar:Artist]
[ti:Song]
Untimed lyric
[00:05.00]Timed lyric
''';

    final lines = LrcParser.parse(source);

    expect(lines, hasLength(1));
    expect(lines.single.text, 'Timed lyric');
  });

  test('ignores malformed timestamps without losing valid lines', () {
    const source = '''
[00:99.00]Invalid
[abc]Invalid
[00:04.00]Valid
''';

    final lines = LrcParser.parse(source);

    expect(lines, hasLength(1));
    expect(lines.single.timestamp, const Duration(seconds: 4));
    expect(lines.single.text, 'Valid');
  });

  group('offset tag (SN-44)', () {
    test('a positive offset shows every line earlier', () {
      final lines = LrcParser.parse('[offset:+500]\n[00:10.00]Line\n');

      expect(
        lines.single.timestamp,
        const Duration(seconds: 9, milliseconds: 500),
      );
    });

    test('a negative offset shows every line later', () {
      final lines = LrcParser.parse('[00:10.00]Line\n[offset:-250]\n');

      expect(
        lines.single.timestamp,
        const Duration(seconds: 10, milliseconds: 250),
      );
    });

    test('an offset never moves a line before the start', () {
      final lines = LrcParser.parse('[OFFSET: 2000]\n[00:01.00]Intro\n');

      expect(lines.single.timestamp, Duration.zero);
    });

    test('a malformed offset is ignored', () {
      final lines = LrcParser.parse('[offset:soon]\n[00:10.00]Line\n');

      expect(lines.single.timestamp, const Duration(seconds: 10));
    });
  });

  test('lines sharing a timestamp keep their file order (SN-44)', () {
    final source = [
      for (var i = 0; i < 40; i++)
        '[00:${(i % 4).toString().padLeft(2, '0')}.00]Line $i',
    ].join('\n');

    final lines = LrcParser.parse(source);

    for (var second = 0; second < 4; second++) {
      final texts = lines
          .where((line) => line.timestamp == Duration(seconds: second))
          .map((line) => line.text)
          .toList();
      expect(texts, [for (var i = second; i < 40; i += 4) 'Line $i']);
    }
  });

  group('untimed lines in timed lyrics (SN-44)', () {
    test('continue the timed line above them', () {
      final lines = LrcParser.parse(
        '[ar:Artist]\n'
        '[00:01.00]First line\n'
        'and its second half\n'
        '\n'
        '[00:05.00]Next line\n',
      );

      expect(lines.map((line) => line.text), [
        'First line\nand its second half',
        'Next line',
      ]);
    });

    test('continue every copy of a multi-timestamp line', () {
      final lines = LrcParser.parse(
        '[00:01.00][00:09.00]Chorus\nsung twice\n[00:05.00]Verse\n',
      );

      expect(lines.map((line) => line.text), [
        'Chorus\nsung twice',
        'Verse',
        'Chorus\nsung twice',
      ]);
    });

    test('a blank line ends the lyric above', () {
      final lines = LrcParser.parse(
        '[00:01.00]Last line\n\nWritten by someone\n',
      );

      expect(lines.map((line) => line.text), ['Last line']);
    });

    test('text before the first timestamp and tags stay ignored', () {
      final lines = LrcParser.parse(
        'Credits: someone\n[ti:Title]\n[00:02.00]Only line\n[length:03:00]\n',
      );

      expect(lines.map((line) => line.text), ['Only line']);
    });
  });

  // App Update 1.3 (REF-1.3-07): enhanced LRC word timings.
  group('enhanced word timings', () {
    test('are removed from the text; the line keeps its own time', () {
      final lines = LrcParser.parse(
        '[00:12.00]<00:12.00>Hold <00:12.50>me <00:13.10>close\n'
        '[00:15.00]<00:15.00>Let <00:15.40>go<00:16.00>\n',
      );

      expect(lines.map((line) => line.text), ['Hold me close', 'Let go']);
      expect(lines.map((line) => line.timestamp.inMilliseconds), [
        12000,
        15000,
      ]);
    });

    test('syllable timings inside a word join the word', () {
      final lines = LrcParser.parse('[00:01.00]Hel<00:01.30>lo');
      expect(lines.single.text, 'Hello');
    });

    test('lines without word timings keep their spacing', () {
      final lines = LrcParser.parse('[00:01.00]A  gap   kept');
      expect(lines.single.text, 'A  gap   kept');
    });

    test('a continuation line loses its word timings too', () {
      final lines = LrcParser.parse(
        '[00:01.00]First\n<00:02.00>wrapped <00:02.40>line\n',
      );
      expect(lines.single.text, 'First\nwrapped line');
    });

    test('angle-bracket text that is not a time stays', () {
      final lines = LrcParser.parse('[00:01.00]<3 you');
      expect(lines.single.text, '<3 you');
    });
  });

  test('returns immutable parsed results', () {
    final lines = LrcParser.parse('[00:01.00]Line');

    expect(() => lines.add(lines.single), throwsUnsupportedError);
  });
}
