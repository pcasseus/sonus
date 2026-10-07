import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_rate_limiter.dart';

void main() {
  test('first request does not delay', () async {
    var now = DateTime.utc(2026, 1, 1);
    final delays = <Duration>[];

    final limiter = MusicBrainzRateLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await limiter.waitForTurn();

    expect(delays, isEmpty);
  });

  test('second request waits for remaining one-second interval', () async {
    var now = DateTime.utc(2026, 1, 1);
    final delays = <Duration>[];

    final limiter = MusicBrainzRateLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await limiter.waitForTurn();

    now = now.add(const Duration(milliseconds: 250));

    await limiter.waitForTurn();

    expect(delays, [const Duration(milliseconds: 750)]);
  });

  test('request after full interval does not delay', () async {
    var now = DateTime.utc(2026, 1, 1);
    final delays = <Duration>[];

    final limiter = MusicBrainzRateLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await limiter.waitForTurn();

    now = now.add(const Duration(seconds: 1));

    await limiter.waitForTurn();

    expect(delays, isEmpty);
  });

  test('concurrent calls are serialized through limiter', () async {
    var now = DateTime.utc(2026, 1, 1);
    final delays = <Duration>[];

    final limiter = MusicBrainzRateLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await Future.wait([
      limiter.waitForTurn(),
      limiter.waitForTurn(),
      limiter.waitForTurn(),
    ]);

    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 1)]);
  });
}
