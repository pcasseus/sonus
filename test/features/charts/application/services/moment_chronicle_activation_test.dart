import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';

/// App Update 1.1: the Moments chronicle starts at the first run of a build
/// that carries it, recorded once, on every build (approved or not).
class _Stores implements MomentRulesActivationStore, MomentChronicleStore {
  String? chronicle;
  var chronicleWrites = 0;
  bool failChronicle = false;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String activatedAtUtc) async {}

  @override
  Future<String?> readCatalogStart(int version) async => null;

  @override
  Future<void> writeCatalogStart(int version, String fromUtc) async {}

  @override
  Future<String?> readChronicleStart() async {
    if (failChronicle) throw StateError('unreadable');
    return chronicle;
  }

  @override
  Future<void> writeChronicleStart(String fromUtc) async {
    chronicleWrites++;
    chronicle = fromUtc;
  }
}

void main() {
  test('the first run records the chronicle start; later runs keep it', () {
    final stores = _Stores();
    var now = DateTime.utc(2026, 11, 6, 15);

    Future<DateTime?> start() => MomentRulesActivation(
      store: stores,
      chronicle: stores,
      approved: false,
      now: () => now,
    ).rules().then((rules) => rules.chronicleFromUtc);

    return start().then((first) async {
      expect(first, DateTime.utc(2026, 11, 6, 15));
      now = DateTime.utc(2026, 11, 9);
      expect(await start(), first, reason: 'never moved');
      expect(stores.chronicleWrites, 1);
    });
  });

  test('stories before the start are not chronicled', () async {
    final stores = _Stores()..chronicle = '2026-11-06T15:00:00.000Z';
    final rules = await MomentRulesActivation(
      store: stores,
      chronicle: stores,
      approved: false,
    ).rules();

    expect(rules.chronicles(DateTime.utc(2026, 11, 6, 14, 59)), isFalse);
    expect(rules.chronicles(DateTime.utc(2026, 11, 6, 15)), isTrue);
    expect(rules.activatedAtUtc, isNull, reason: 'refined flag untouched');
  });

  test('an unreadable start means no chronicle this run', () async {
    final stores = _Stores()..failChronicle = true;
    final rules = await MomentRulesActivation(
      store: stores,
      chronicle: stores,
      approved: false,
    ).rules();

    expect(rules.chronicleFromUtc, isNull);
    expect(stores.chronicleWrites, 0);
  });

  test('without a chronicle store nothing is chronicled', () async {
    final rules = await MomentRulesActivation(
      store: _Stores(),
      approved: false,
    ).rules();

    expect(rules.chronicleFromUtc, isNull);
  });
}
