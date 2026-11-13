// App Update 1.2, REF-19: artist-dominance Moments start at the first run
// of a build that carries them, recorded once, on every build.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';

class _Stores
    implements
        MomentRulesActivationStore,
        MomentDominanceStore,
        MomentJointControlStore {
  String? joint;

  String? dominance;
  var writes = 0;
  bool failReads = false;
  bool dropWrites = false;

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String activatedAtUtc) async {}

  @override
  Future<String?> readCatalogStart(int version) async => null;

  @override
  Future<void> writeCatalogStart(int version, String fromUtc) async {}

  @override
  Future<String?> readDominanceStart() async {
    if (failReads) throw StateError('unreadable');
    return dominance;
  }

  @override
  Future<void> writeDominanceStart(String fromUtc) async {
    writes++;
    if (!dropWrites) dominance = fromUtc;
  }

  @override
  Future<String?> readJointControlStart() async {
    if (failReads) throw StateError('unreadable');
    return joint;
  }

  @override
  Future<void> writeJointControlStart(String fromUtc) async {
    writes++;
    if (!dropWrites) joint = fromUtc;
  }
}

void main() {
  test('the first run records the start; later runs never move it', () async {
    final stores = _Stores();
    var now = DateTime.utc(2026, 11, 12, 9);
    Future<DateTime?> start() => MomentRulesActivation(
      store: stores,
      dominance: stores,
      approved: false,
      now: () => now,
    ).dominanceFrom();

    final first = await start();
    expect(first, DateTime.utc(2026, 11, 12, 9));
    now = DateTime.utc(2026, 12, 1);
    expect(await start(), first);
    expect(stores.writes, 1);
  });

  test('a stored start is kept as it was', () async {
    final stores = _Stores()..dominance = '2026-11-12T09:00:00.000Z';
    final start = await MomentRulesActivation(
      store: stores,
      dominance: stores,
      now: () => DateTime.utc(2027),
    ).dominanceFrom();
    expect(start, DateTime.utc(2026, 11, 12, 9));
    expect(stores.writes, 0);
  });

  test('unreadable, unsaved or unreadable text: none this run', () async {
    for (final stores in [
      _Stores()..failReads = true,
      _Stores()..dropWrites = true,
      _Stores()..dominance = 'not a time',
      _Stores()..dominance = '2026-11-12T09:00:00.000',
    ]) {
      expect(
        await MomentRulesActivation(
          store: stores,
          dominance: stores,
        ).dominanceFrom(),
        isNull,
      );
    }
  });

  test('without a store nothing is recorded', () async {
    expect(
      await MomentRulesActivation(store: _Stores()).dominanceFrom(),
      isNull,
    );
  });

  group('joint chart control has its own start', () {
    test('recorded once, independently of the dominance start', () async {
      final stores = _Stores()..dominance = '2026-11-12T09:00:00.000Z';
      var now = DateTime.utc(2027, 2, 1);
      Future<DateTime?> start() => MomentRulesActivation(
        store: stores,
        dominance: stores,
        jointControl: stores,
        now: () => now,
      ).jointControlFrom();

      expect(await start(), DateTime.utc(2027, 2, 1));
      now = DateTime.utc(2027, 3, 1);
      expect(await start(), DateTime.utc(2027, 2, 1));
      expect(stores.dominance, '2026-11-12T09:00:00.000Z');
      expect(stores.writes, 1);
    });

    test('unreadable or unsaved: none this run; no store: none', () async {
      for (final stores in [
        _Stores()..failReads = true,
        _Stores()..dropWrites = true,
      ]) {
        expect(
          await MomentRulesActivation(
            store: stores,
            jointControl: stores,
          ).jointControlFrom(),
          isNull,
        );
      }
      expect(
        await MomentRulesActivation(store: _Stores()).jointControlFrom(),
        isNull,
      );
    });
  });

  group('recorded when the rules first load, not at the next finalized '
      'week', () {
    test(
      'loading the rules records both starts, with no week finalized',
      () async {
        final stores = _Stores();
        await MomentRulesActivation(
          store: stores,
          dominance: stores,
          jointControl: stores,
          now: () => DateTime.utc(2026, 11, 13, 0, 31),
        ).rules();

        expect(stores.dominance, '2026-11-13T00:31:00.000Z');
        expect(stores.joint, '2026-11-13T00:31:00.000Z');
      },
    );

    test('the rules and a finalization pass asking together record one '
        'start', () async {
      final stores = _Stores();
      var now = DateTime.utc(2026, 11, 13);
      final activation = MomentRulesActivation(
        store: stores,
        dominance: stores,
        now: () => now = now.add(const Duration(seconds: 1)),
      );

      final starts = await Future.wait([
        activation.rules().then((_) => activation.dominanceFrom()),
        activation.dominanceFrom(),
        activation.dominanceFrom(),
      ]);

      expect(stores.writes, 1);
      expect(starts.toSet(), hasLength(1));
    });

    test('a failed attempt is tried again later', () async {
      final stores = _Stores()..failReads = true;
      final activation = MomentRulesActivation(
        store: stores,
        dominance: stores,
        now: () => DateTime.utc(2026, 11, 13),
      );

      expect(await activation.dominanceFrom(), isNull);
      stores.failReads = false;
      expect(await activation.dominanceFrom(), DateTime.utc(2026, 11, 13));
    });
  });
}
