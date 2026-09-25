import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/models/lyric_line.dart';

void main() {
  test('compares lyric lines by timestamp and text', () {
    const first = LyricLine(
      timestamp: Duration(seconds: 12, milliseconds: 340),
      text: 'Hello',
    );
    const same = LyricLine(
      timestamp: Duration(seconds: 12, milliseconds: 340),
      text: 'Hello',
    );
    const different = LyricLine(
      timestamp: Duration(seconds: 13),
      text: 'Hello',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(different));
  });
}
