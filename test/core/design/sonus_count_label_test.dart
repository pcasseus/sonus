import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_count_label.dart';

void main() {
  test('uses the singular for exactly one', () {
    expect(sonusCount(1, 'stream'), '1 stream');
    expect(sonusCount(0, 'stream'), '0 streams');
    expect(sonusCount(2, 'stream'), '2 streams');
    expect('1 lifetime ${sonusCountNoun(1, 'stream')}', '1 lifetime stream');
    expect('1 weekly ${sonusCountNoun(1, 'stream')}', '1 weekly stream');
  });

  test('takes an irregular plural', () {
    expect(sonusCount(1, 'entry', plural: 'entries'), '1 entry');
    expect(sonusCount(3, 'entry', plural: 'entries'), '3 entries');
  });
}
