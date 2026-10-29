// SN-50 R2: the Moments rules start only in an approved build, at an
// instant recorded once.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';

void main() {
  final firstRun = DateTime.utc(2026, 11, 9, 14, 30);

  test('builds are unapproved unless compiled with the approval', () {
    expect(MomentRulesActivation.buildApproved, isFalse);
  });

  test('an unapproved build never activates, and never reads or writes the '
      'instant', () async {
    final store = _Store('2026-11-02T00:00:00.000Z');

    final rules = await MomentRulesActivation(
      store: store,
      now: () => firstRun,
    ).rules();

    expect(rules.activatedAtUtc, isNull);
    expect(store.reads, 0);
    expect(store.writes, 0);
  });

  test('the first approved run records the instant once; later runs and '
      'calls never move it', () async {
    final store = _Store();
    final activation = MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun,
    );

    final results = await Future.wait([activation.rules(), activation.rules()]);
    final later = await MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun.add(const Duration(days: 30)),
    ).rules();

    expect(results.map((rules) => rules.activatedAtUtc), [firstRun, firstRun]);
    expect(later.activatedAtUtc, firstRun);
    expect(store.writes, 1);
    expect(store.value, firstRun.toIso8601String());
  });

  test('a restored instant is used as it is', () async {
    final store = _Store('2026-11-02T08:00:00.000Z');

    final rules = await MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun,
    ).rules();

    expect(rules.activatedAtUtc, DateTime.utc(2026, 11, 2, 8));
    expect(store.writes, 0);
  });

  test('an instant that is not durable activates nothing, and is tried '
      'again', () async {
    final store = _Store()..dropWrites = true;
    final activation = MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun,
    );

    expect((await activation.rules()).activatedAtUtc, isNull);

    store.dropWrites = false;
    expect((await activation.rules()).activatedAtUtc, firstRun);
  });

  test('a storage failure activates nothing', () async {
    final store = _Store()..failure = StateError('preferences unavailable');

    final rules = await MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun,
    ).rules();

    expect(rules.activatedAtUtc, isNull);
    expect(store.writes, 0);
  });

  test('an unreadable instant activates nothing and is never '
      'replaced', () async {
    final store = _Store('not a time');

    final rules = await MomentRulesActivation(
      store: store,
      approved: true,
      now: () => firstRun,
    ).rules();

    expect(rules.activatedAtUtc, isNull);
    expect(store.writes, 0);
    expect(store.value, 'not a time');
  });
}

class _Store implements MomentRulesActivationStore {
  _Store([this.value]);

  String? value;
  bool dropWrites = false;
  Object? failure;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return value;
  }

  @override
  Future<void> write(String activatedAtUtc) async {
    writes++;
    if (!dropWrites) value = activatedAtUtc;
  }
}
