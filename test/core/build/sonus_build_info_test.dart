import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/build/sonus_build_info.dart';

void main() {
  test('a build without Git metadata says so instead of guessing', () {
    const info = SonusBuildInfo(
      commit: '',
      time: '  ',
      mode: SonusBuildMode.debug,
    );

    expect(info.hasCommit, isFalse);
    expect(info.commitLabel, 'Not recorded — built without Git metadata');
    expect(info.timeLabel, 'Not recorded');
    expect(info.modeLabel, 'Debug');
    expect(
      info.displayString,
      'Not recorded — built without Git metadata · Debug',
    );
  });

  test('a recorded build shows its commit, type and time', () {
    const info = SonusBuildInfo(
      commit: '4d640c4-dirty',
      time: '2026-11-06T10:00:00Z',
      mode: SonusBuildMode.release,
    );

    expect(info.commitLabel, '4d640c4-dirty');
    expect(info.timeLabel, '2026-11-06T10:00:00Z');
    expect(
      info.displayString,
      '4d640c4-dirty · Release · 2026-11-06T10:00:00Z',
    );
  });

  test('tests run without the defines and in debug mode', () {
    expect(SonusBuildInfo.current.hasCommit, isFalse);
    expect(SonusBuildInfo.current.mode, SonusBuildMode.debug);
  });
}
