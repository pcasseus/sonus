// App Update 1.3 new-release debuts start only with a build whose
// generation and wording are both approved: such a build records a
// write-once start on its first run; this build (both off) records none.
// The earlier write-once starts are never touched.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';
import 'package:sonus_next/features/charts/data/services/shared_preferences_moment_rules_activation_store.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_eligibility.dart';
import 'package:sonus_next/features/charts/presentation/editorial/new_release_debut_headlines.dart';
import 'package:sonus_next/features/charts/presentation/scopes/charts_scope.dart';

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

const _key = SharedPreferencesMomentRulesActivationStore.newReleaseDebutsKey;

/// Starts an earlier build recorded; none may move.
final _earlier = {
  SharedPreferencesMomentRulesActivationStore.devicePolishKey:
      '2026-10-30T10:00:00.000Z',
  SharedPreferencesMomentRulesActivationStore.chronicleKey:
      '2026-11-02T10:00:00.000Z',
  SharedPreferencesMomentRulesActivationStore.dominanceKey:
      '2026-11-13T01:13:22.000Z',
  SharedPreferencesMomentRulesActivationStore.jointControlKey:
      '2026-11-13T08:05:50.843681Z',
};

void main() {
  test('this build has new-release debuts approved (2026-11-16)', () {
    expect(NewReleaseDebutActivation.generationApproved, isTrue);
    expect(NewReleaseDebutHeadlines.approved, isTrue);
    expect(_key, 'charts.moments.new_release_debuts_1_3_from_utc');
  });

  test('switched off: no start is recorded and the rules carry none', () async {
    final preferences = _Preferences()..values.addAll(_earlier);
    final activation = deviceMomentRulesActivation(
      SharedPreferencesMomentRulesActivationStore(preferences),
      newReleaseDebutsApproved: false,
    );

    final rules = await activation.rules();

    expect(rules.newReleaseDebutsFromUtc, isNull);
    expect(await activation.newReleaseDebutsFrom(), isNull);
    expect(preferences.values, isNot(contains(_key)));
    expect(preferences.values, _earlier);
  });

  test('approved: recorded once on the first run, read back after a '
      'restart, never moved, earlier starts untouched', () async {
    final preferences = _Preferences()..values.addAll(_earlier);
    MomentRulesActivation build() => deviceMomentRulesActivation(
      SharedPreferencesMomentRulesActivationStore(preferences),
      newReleaseDebutsApproved: true,
    );

    final first = await build().rules();
    expect(first.newReleaseDebutsFromUtc, isNotNull);
    final recorded = preferences.values[_key];
    expect(recorded, first.newReleaseDebutsFromUtc!.toIso8601String());

    // A restart: a new activation reading the same preferences.
    final restarted = await build().rules();
    expect(restarted.newReleaseDebutsFromUtc, first.newReleaseDebutsFromUtc);
    expect(preferences.values[_key], recorded);
    for (final MapEntry(:key, :value) in _earlier.entries) {
      expect(preferences.values[key], value, reason: key);
    }
  });
}
