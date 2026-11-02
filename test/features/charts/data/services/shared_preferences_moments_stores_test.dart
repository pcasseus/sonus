// SN-50 R2/R6: what the Moments preferences store, and how they read back.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonus_next/features/charts/application/services/moments_last_seen_store.dart';
import 'package:sonus_next/features/charts/data/services/shared_preferences_moment_rules_activation_store.dart';
import 'package:sonus_next/features/charts/data/services/shared_preferences_moments_last_seen_store.dart';

void main() {
  group('Moments last-seen mark', () {
    test('keeps the time and story id, ids with separators included', () async {
      final preferences = _Preferences();
      final store = SharedPreferencesMomentsLastSeenStore(preferences);

      await store.write(
        MomentsSeenMark(
          occurredAtUtc: DateTime.utc(2026, 11, 4, 9),
          storyId: 'moment-feed:a|b',
        ),
      );
      final mark = await store.read();

      expect(mark?.occurredAtUtc, DateTime.utc(2026, 11, 4, 9));
      expect(mark?.storyId, 'moment-feed:a|b');
    });

    test('keeps a feed seen empty', () async {
      final store = SharedPreferencesMomentsLastSeenStore(_Preferences());

      await store.write(const MomentsSeenMark.empty());
      final mark = await store.read();

      expect(mark, isNotNull);
      expect(mark!.occurredAtUtc, isNull);
      expect(mark.isOlderThan(DateTime.utc(2020), ''), isTrue);
    });

    test('nothing stored, or an unreadable or time-only value, is no '
        'mark', () async {
      final preferences = _Preferences();
      final store = SharedPreferencesMomentsLastSeenStore(preferences);
      expect(await store.read(), isNull);

      for (final stored in ['2026-11-04T09:00:00.000Z', 'garbage|id']) {
        preferences.values[SharedPreferencesMomentsLastSeenStore.key] = stored;
        expect(await store.read(), isNull, reason: stored);
      }
    });
  });

  test('the rules activation instant is stored as given', () async {
    final preferences = _Preferences();
    final store = SharedPreferencesMomentRulesActivationStore(preferences);

    expect(await store.read(), isNull);
    await store.write('2026-11-09T14:30:00.000Z');

    expect(await store.read(), '2026-11-09T14:30:00.000Z');
    expect(
      preferences.values[SharedPreferencesMomentRulesActivationStore.key],
      '2026-11-09T14:30:00.000Z',
    );
  });
}

class _Preferences implements SharedPreferencesAsync {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
