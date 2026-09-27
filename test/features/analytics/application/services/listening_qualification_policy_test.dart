import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/listening_qualification_policy.dart';

void main() {
  const policy = ListeningQualificationPolicy();

  group('ListeningQualificationPolicy', () {
    test('uses 30 seconds for an ordinary track', () {
      expect(
        policy.thresholdFor(const Duration(minutes: 4)),
        const Duration(seconds: 30),
      );
    });

    test('uses 30 seconds for a track exactly 30 seconds long', () {
      expect(
        policy.thresholdFor(const Duration(seconds: 30)),
        const Duration(seconds: 30),
      );
    });

    test('uses half of a short track when half is above five seconds', () {
      expect(
        policy.thresholdFor(const Duration(seconds: 20)),
        const Duration(seconds: 10),
      );
    });

    test('uses five seconds for a short track when half is below minimum', () {
      expect(
        policy.thresholdFor(const Duration(seconds: 8)),
        const Duration(seconds: 5),
      );
    });

    test('never requires more listening than a very short track contains', () {
      expect(
        policy.thresholdFor(const Duration(seconds: 4)),
        const Duration(seconds: 4),
      );
    });

    test('rounds fractional half duration upward', () {
      expect(
        policy.thresholdFor(const Duration(seconds: 11, milliseconds: 1)),
        const Duration(milliseconds: 5501),
      );
    });

    test('unknown duration safely falls back to 30 seconds', () {
      expect(policy.thresholdFor(Duration.zero), const Duration(seconds: 30));
    });

    test('qualifies exactly at the required duration', () {
      expect(
        policy.qualifies(
          listenedDuration: const Duration(seconds: 30),
          trackDuration: const Duration(minutes: 4),
        ),
        isTrue,
      );
    });

    test('does not qualify immediately below the required duration', () {
      expect(
        policy.qualifies(
          listenedDuration: const Duration(seconds: 29, milliseconds: 999),
          trackDuration: const Duration(minutes: 4),
        ),
        isFalse,
      );
    });

    test('qualifies a 20 second track after 10 seconds listened', () {
      expect(
        policy.qualifies(
          listenedDuration: const Duration(seconds: 10),
          trackDuration: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });

    test('does not qualify a 20 second track before 10 seconds listened', () {
      expect(
        policy.qualifies(
          listenedDuration: const Duration(seconds: 9, milliseconds: 999),
          trackDuration: const Duration(seconds: 20),
        ),
        isFalse,
      );
    });

    test('negative listened time never qualifies', () {
      expect(
        policy.qualifies(
          listenedDuration: const Duration(milliseconds: -1),
          trackDuration: const Duration(minutes: 4),
        ),
        isFalse,
      );
    });
  });
}
