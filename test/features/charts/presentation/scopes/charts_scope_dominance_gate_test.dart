// App Update 1.2, REF-19: artist-dominance Moments stay off until their
// lines are approved. A build with draft lines records none and sets no
// start, so the first week counted is the first one finalized after a build
// with approved lines is installed.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonus_next/features/charts/data/services/shared_preferences_moment_rules_activation_store.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';
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

const _dominance = {
  MomentFamily.artistChartSweep,
  MomentFamily.artistTop10Presence,
  MomentFamily.artistHot100Presence,
};

void main() {
  test('the dominance lines are not approved yet', () {
    expect(MomentHeadlines.artistDominanceApproved(), isFalse);
    for (final family in _dominance) {
      expect(MomentHeadlines.approvedFamilies, isNot(contains(family)));
    }
  });

  test('all three families must be approved', () {
    expect(MomentHeadlines.artistDominanceApproved(_dominance), isTrue);
    for (final family in _dominance) {
      expect(
        MomentHeadlines.artistDominanceApproved(
          _dominance.difference({family}),
        ),
        isFalse,
        reason: '$family missing',
      );
    }
  });

  test('with draft lines nothing is recorded and no start is set', () async {
    final preferences = _Preferences();
    final activation = deviceMomentRulesActivation(
      SharedPreferencesMomentRulesActivationStore(preferences),
    );

    expect(await activation.dominanceFrom(), isNull);
    expect(
      preferences.values,
      isNot(contains(SharedPreferencesMomentRulesActivationStore.dominanceKey)),
    );
  });

  test('once approved, the start is set on the first run and kept', () async {
    final preferences = _Preferences();
    final approved = {...MomentHeadlines.approvedFamilies, ..._dominance};
    final activation = deviceMomentRulesActivation(
      SharedPreferencesMomentRulesActivationStore(preferences),
      approved: approved,
    );

    final start = await activation.dominanceFrom();

    expect(start, isNotNull);
    expect(
      preferences.values[SharedPreferencesMomentRulesActivationStore
          .dominanceKey],
      start!.toIso8601String(),
    );
  });

  group('joint chart control waits for its own lines', () {
    test('not approved: never recorded, no start set', () async {
      final preferences = _Preferences();
      final activation = deviceMomentRulesActivation(
        SharedPreferencesMomentRulesActivationStore(preferences),
        approved: {...MomentHeadlines.approvedFamilies, ..._dominance},
      );

      expect(MomentHeadlines.artistJointControlApproved(), isFalse);
      expect(await activation.jointControlFrom(), isNull);
      expect(
        preferences.values,
        isNot(
          contains(SharedPreferencesMomentRulesActivationStore.jointControlKey),
        ),
      );
    });

    test('approved: its start is set on the first run', () async {
      final preferences = _Preferences();
      final activation = deviceMomentRulesActivation(
        SharedPreferencesMomentRulesActivationStore(preferences),
        approved: {MomentFamily.artistJointControl},
      );

      final start = await activation.jointControlFrom();
      expect(start, isNotNull);
      expect(
        preferences.values[SharedPreferencesMomentRulesActivationStore
            .jointControlKey],
        start!.toIso8601String(),
      );
      expect(await activation.dominanceFrom(), isNull);
    });
  });
}
