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

  test('compact listening time for narrow tiles (App Update 1.1)', () {
    expect(sonusListeningTimeCompact(Duration.zero), '0 min');
    expect(sonusListeningTimeCompact(const Duration(seconds: 1)), '<1 min');
    expect(sonusListeningTimeCompact(const Duration(seconds: 59)), '<1 min');
    expect(sonusListeningTimeCompact(const Duration(minutes: 1)), '1 min');
    expect(sonusListeningTimeCompact(const Duration(minutes: 45)), '45 min');
    expect(sonusListeningTimeCompact(const Duration(hours: 2)), '2h');
    expect(
      sonusListeningTimeCompact(const Duration(hours: 26, minutes: 5)),
      '26h 5m',
    );
    // The spoken form stays descriptive.
    expect(sonusListeningTime(const Duration(seconds: 40)), 'under a minute');
  });
}
