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

  test('returns immutable parsed results', () {
    final lines = LrcParser.parse('[00:01.00]Line');

    expect(() => lines.add(lines.single), throwsUnsupportedError);
  });
}
