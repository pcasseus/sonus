import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';

void main() {
  test('repeat cycles Off, All, One, then Off again (SN-50 D-Q12)', () {
    var mode = PlaybackRepeatMode.off;
    final seen = <PlaybackRepeatMode>[];
    for (var i = 0; i < 4; i++) {
      mode = mode.next;
      seen.add(mode);
    }

    expect(seen, [
      PlaybackRepeatMode.all,
      PlaybackRepeatMode.one,
      PlaybackRepeatMode.off,
      PlaybackRepeatMode.all,
    ]);
  });
}
