// SN-50 device polish: rising-song stories name the places climbed, from
// the climb wording's start on; earlier stories keep their published words.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/moment_rules_activation.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_climb.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_headlines.dart';

import 'moment_editorial_test.dart' show FakeLookups, event, items, song;

final _start = DateTime.utc(2026, 11, 2);
final _before = DateTime.utc(2026, 10, 26, 12);
final _after = DateTime.utc(2026, 11, 3, 12);

MomentEditorialDesk _desk(ChartMomentRules rules) => MomentEditorialDesk(
  lookups: FakeLookups(artists: const {'artist-a': 'Name artist-a'}),
  rules: rules,
);

final _climbRules = ChartMomentRules(devicePolishFromUtc: _start);

MomentStory _story(
  ChartMomentRules rules, {
  required ChartMomentEventType type,
  required int rank,
  int? previousRank,
  DateTime? at,
  String id = 's1',
  ChartMomentScope scope = ChartMomentScope.allTime,
  List<ChartMomentEventType> extra = const [],
}) {
  final entity = song(id);
  final stories = _desk(rules).compose(
    items([
      event(
        type,
        entity: entity,
        scope: scope,
        at: at ?? _after,
        rank: rank,
        previousRank: previousRank,
        previousPeak: previousRank,
      ),
      for (final other in extra)
        event(
          other,
          entity: entity,
          scope: scope,
          at: at ?? _after,
          rank: rank,
          previousRank: previousRank,
        ),
    ]),
  );
  return stories.single;
}

class _MemoryStore
    implements MomentRulesActivationStore, MomentDevicePolishStore {
  String? climb;
  int climbWrites = 0;
  bool failClimb = false;

  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String activatedAtUtc) async {}
  @override
  Future<String?> readCatalogStart(int version) async => null;
  @override
  Future<void> writeCatalogStart(int version, String fromUtc) async {}
  @override
  Future<String?> readDevicePolishStart() async {
    if (failClimb) throw StateError('unreadable');
    return climb;
  }

  @override
  Future<void> writeDevicePolishStart(String fromUtc) async {
    climbWrites++;
    climb = fromUtc;
  }
}

void main() {
  group('climb wording', () {
    test('a rising song names the places climbed after the start', () {
      final story = _story(
        _climbRules,
        type: ChartMomentEventType.rankRise,
        rank: 8,
        previousRank: 20,
      );
      expect(story.family, MomentFamily.songBigClimb);
      expect(story.headline, contains('12 places'));
      expect(story.headline, contains('#8'));
      expect(story.variantId, startsWith('climb-'));
      expect(story.climb, 12);
    });

    test('a Bubbling Under climb names its own chart', () {
      final story = _story(
        _climbRules,
        type: ChartMomentEventType.rankRise,
        rank: 126,
        previousRank: 130,
      );
      expect(story.headline, contains('4 places'));
      expect(story.headline, contains('#126'));
      expect(story.headline, contains('Bubbling Under'));
    });

    test('one place is singular', () {
      final story = _story(
        _climbRules,
        type: ChartMomentEventType.rankRise,
        rank: 8,
        previousRank: 9,
      );
      expect(story.headline, contains('1 place '));
      expect(story.headline, isNot(contains('1 places')));
    });

    test('new peaks and #1s name the climb too', () {
      final peak = _story(
        _climbRules,
        type: ChartMomentEventType.newPeak,
        rank: 5,
        previousRank: 15,
      );
      expect(peak.family, MomentFamily.songNewPeak);
      expect(peak.headline, contains('10 places'));

      final top = _story(
        _climbRules,
        type: ChartMomentEventType.returnToNumberOne,
        rank: 1,
        previousRank: 4,
      );
      expect(top.family, MomentFamily.songReturnsToNumberOne);
      expect(top.headline, contains('3 places'));
      expect(top.headline, contains('#1'));
    });

    test('stories from before the start keep their published words', () {
      final legacy = _story(
        ChartMomentRules.legacy,
        type: ChartMomentEventType.rankRise,
        rank: 8,
        previousRank: 20,
        at: _before,
      );
      final revised = _story(
        _climbRules,
        type: ChartMomentEventType.rankRise,
        rank: 8,
        previousRank: 20,
        at: _before,
      );
      expect(revised.headline, legacy.headline);
      expect(revised.variantId, legacy.variantId);
      expect(
        MomentHeadlines.legacyOf(MomentFamily.songBigClimb).map((v) => v.id),
        contains(revised.variantId),
      );
      // The climb is still shown beside the old words.
      expect(revised.climb, 12);
    });

    test('without a recorded start nothing changes words', () {
      final story = _story(
        ChartMomentRules.legacy,
        type: ChartMomentEventType.rankRise,
        rank: 8,
        previousRank: 20,
      );
      expect(story.variantId, isNot(startsWith('climb-')));
    });

    test('a move from Bubbling Under into the Hot 100 is not a climb', () {
      final story = _story(
        _climbRules,
        type: ChartMomentEventType.rankRise,
        rank: 90,
        previousRank: 120,
      );
      expect(story.climb, isNull);
      expect(story.variantId, isNot(startsWith('climb-')));
    });

    test('debuts and re-entries have no climb', () {
      final debut = _story(
        _climbRules,
        type: ChartMomentEventType.debut,
        rank: 8,
      );
      expect(debut.climb, isNull);
      expect(debut.headline, isNot(contains('places')));

      final reentry = _story(
        _climbRules,
        type: ChartMomentEventType.newPeak,
        rank: 8,
        previousRank: 30,
        extra: const [ChartMomentEventType.reentry],
      );
      expect(reentry.climb, isNull);
      expect(reentry.variantId, isNot(startsWith('climb-')));
    });

    test('both voices have climb lines for every headline family', () {
      for (final family in MomentClimb.headlineFamilies) {
        final publishers = {
          for (final v in ClimbHeadlines.of(family)) v.publisher,
        };
        expect(publishers, hasLength(2), reason: family.name);
        expect(
          MomentHeadlines.approvedFamilies,
          contains(family),
          reason: family.name,
        );
      }
    });

    test('statesClimb compares instants', () {
      expect(_climbRules.statesClimb(_start), isTrue);
      expect(
        _climbRules.statesClimb(_start.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(ChartMomentRules.legacy.statesClimb(_after), isFalse);
    });
  });

  group('climb wording start', () {
    test('is recorded once and kept, with refined Moments off', () async {
      final store = _MemoryStore();
      final first = MomentRulesActivation(
        store: store,
        approved: false,
        devicePolish: store,
        now: () => _start,
      );
      final rules = await first.rules();
      expect(rules.devicePolishFromUtc, _start);
      expect(rules.activatedAtUtc, isNull);
      expect(
        rules.appliesTo(
          scope: ChartMomentScope.allTime,
          occurredAt: _after,
          weekStartUtc: _after,
        ),
        isFalse,
      );

      final later = MomentRulesActivation(
        store: store,
        approved: false,
        devicePolish: store,
        now: () => _after,
      );
      expect((await later.rules()).devicePolishFromUtc, _start);
      expect(store.climbWrites, 1);
    });

    test('an unreadable start keeps the first wording', () async {
      final store = _MemoryStore()..failClimb = true;
      final rules = await MomentRulesActivation(
        store: store,
        approved: false,
        devicePolish: store,
        now: () => _start,
      ).rules();
      expect(rules.devicePolishFromUtc, isNull);
      expect(store.climbWrites, 0);
    });

    test('without a store the rules are the legacy ones', () async {
      final rules = await MomentRulesActivation(
        store: _MemoryStore(),
        approved: false,
      ).rules();
      expect(identical(rules, ChartMomentRules.legacy), isTrue);
    });
  });
}
