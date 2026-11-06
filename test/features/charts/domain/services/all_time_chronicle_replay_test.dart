import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

/// App Update 1.1: the all-time replay's chronicle facts (daily #1 holds,
/// Hot 100 and Top 200 exits, Hot 100 and zone returns, completed chart
/// days). Times are local, so chart days close at local midnight.
class _Plays {
  _Plays([DateTime? start]) : _start = start ?? DateTime(2026, 10, 5, 12);

  final DateTime _start;
  final List<ChartRankingEvent> events = [];
  var _clock = 0;
  var _ids = 0;

  DateTime get _now => _start.add(Duration(minutes: _clock));

  /// [times] plays of [entity], one minute apart.
  void play(String entity, [int times = 1]) {
    for (var i = 0; i < times; i++) {
      events.add(
        ChartRankingEvent(
          entityId: entity,
          qualifiedAt: _now.toUtc(),
          sourceEventId: 'play-${++_ids}',
        ),
      );
      _clock++;
    }
  }

  /// Moves to [hour]:00 local on the day [days] after the current one.
  void nextDay({int days = 1, int hour = 12}) {
    final now = _now;
    final target = DateTime(now.year, now.month, now.day + days, hour);
    _clock = target.difference(_start).inMinutes;
  }

  DateTime get now => _now;
}

void main() {
  const replay = AllTimeHistoryReplay();
  final chronicle = DateTime(2026, 10, 1).toUtc();

  AllTimeReplayResult run(
    _Plays plays, {
    DateTime? chronicleFrom,
    bool noChronicle = false,
    Set<String> standings = const {},
  }) => replay.run(
    events: plays.events,
    referenceLocal: plays.now,
    chronicleFromUtc: noChronicle ? null : chronicleFrom ?? chronicle,
    collectDayStandings: standings,
  );

  List<AllTimeAchievement> ofType(
    AllTimeReplayResult result,
    AllTimeAchievementType type,
  ) => [
    for (final achievement in result.achievements)
      if (achievement.type == type) achievement,
  ];

  group('daily #1 holds', () {
    test('one story per completed day, with consecutive and cumulative '
        'days', () {
      final plays = _Plays()..play('a', 3);
      plays
        ..nextDay()
        ..play('a')
        ..nextDay()
        ..play('b', 5)
        ..nextDay()
        ..play('a', 3)
        ..nextDay();

      final days = ofType(run(plays), AllTimeAchievementType.numberOneDay);

      expect(days.map((d) => d.entityId), ['a', 'a', 'b', 'a']);
      expect(days.map((d) => d.milestone), [1, 2, 1, 1]);
      expect(days.map((d) => d.cumulative), [1, 2, 1, 3]);
      expect(days.map((d) => d.playId), [
        'day:2026-10-05',
        'day:2026-10-06',
        'day:2026-10-07',
        'day:2026-10-08',
      ]);
      // A day closes at local midnight.
      expect(days.first.occurredAt, DateTime(2026, 10, 6).toUtc());
    });

    test('the running day is never reported, however often the app opens', () {
      final plays = _Plays()..play('a', 2);

      for (var open = 0; open < 3; open++) {
        expect(
          ofType(run(plays), AllTimeAchievementType.numberOneDay),
          isEmpty,
        );
      }
    });

    test('replaying gives the same keys, so saving twice adds nothing', () {
      final plays = _Plays()..play('a', 2);
      plays.nextDay(days: 2);

      String keys() => ofType(
        run(plays),
        AllTimeAchievementType.numberOneDay,
      ).map((d) => d.deduplicationKey('songs')).join(',');

      expect(keys(), keys());
      expect(keys().split(','), hasLength(2));
    });

    test('days without plays still close: the leader keeps its run', () {
      final plays = _Plays()..play('a', 2);
      plays.nextDay(days: 4);

      final days = ofType(run(plays), AllTimeAchievementType.numberOneDay);

      expect(days.map((d) => d.milestone), [1, 2, 3, 4]);
      expect(run(plays).daysOf('a').numberOneRun, 4);
      expect(run(plays).observedDays, 4);
    });

    test('nothing before the chronicle start, and nothing without it', () {
      final plays = _Plays()..play('a', 2);
      plays.nextDay(days: 3);

      expect(
        ofType(
          run(plays, noChronicle: true),
          AllTimeAchievementType.numberOneDay,
        ),
        isEmpty,
      );
      final days = ofType(
        run(plays, chronicleFrom: DateTime(2026, 10, 7).toUtc()),
        AllTimeAchievementType.numberOneDay,
      );
      // Days ending at or after the start: Oct 6 (ends Oct 7 00:00) and
      // Oct 7.
      expect(days.map((d) => d.playId), ['day:2026-10-06', 'day:2026-10-07']);
      // The counts still include the earlier days.
      expect(days.map((d) => d.milestone), [2, 3]);
    });
  });

  group('Hot 100 and Top 200 boundaries', () {
    _Plays fullHot100() {
      final plays = _Plays();
      for (var i = 0; i < 100; i++) {
        plays.play('e${i.toString().padLeft(3, '0')}', 2);
      }
      return plays;
    }

    test('a song passing into the Hot 100 pushes #100 to #101: a Hot 100 '
        'exit, still on the chart', () {
      final plays = fullHot100()
        ..nextDay()
        ..play('n', 3);

      final result = run(plays);
      final exits = ofType(result, AllTimeAchievementType.hot100Exit);

      expect(exits.single.entityId, 'e099');
      expect(exits.single.previousRank, 100);
      expect(exits.single.rank, 101);
      expect(exits.single.milestone, 1, reason: 'one completed Hot 100 day');
      expect(exits.single.sourceId, isNot(exits.single.playId));
      expect(ofType(result, AllTimeAchievementType.chartExit), isEmpty);
    });

    test('no exit story for a song that never finished a day there', () {
      final plays = fullHot100()..play('n', 3);

      expect(ofType(run(plays), AllTimeAchievementType.hot100Exit), isEmpty);
    });

    test('back from Bubbling Under to a Hot 100 it charted on: a return', () {
      final plays = fullHot100()
        ..nextDay()
        ..play('n', 3)
        ..play('e099');

      final returns = ofType(run(plays), AllTimeAchievementType.hot100Return);

      expect(returns.single.entityId, 'e099');
      expect(returns.single.previousRank, 101);
      expect(returns.single.rank, lessThanOrEqualTo(100));
    });

    test('a newcomer pushing #200 out: a Top 200 exit with its days', () {
      final plays = _Plays();
      for (var i = 0; i < 200; i++) {
        plays.play('e${i.toString().padLeft(3, '0')}', 2);
      }
      plays
        ..nextDay()
        ..play('n', 3);

      final result = run(plays);
      final exit = ofType(result, AllTimeAchievementType.chartExit).single;

      expect(exit.entityId, 'e199');
      expect(exit.previousRank, 200);
      expect(exit.milestone, 1);
      expect(result.daysOf('e199').chartDays, 1);
      expect(result.daysOf('e199').hot100Days, 0);
    });
  });

  group('zone returns', () {
    test('back into zones it reached before; first entries are not '
        'returns', () {
      final plays = _Plays()..play('x', 5);
      for (var i = 0; i < 11; i++) {
        plays.play('o${i.toString().padLeft(2, '0')}', 6);
      }
      plays.play('x', 2);

      final returns = ofType(
        run(plays),
        AllTimeAchievementType.thresholdReturn,
      ).where((a) => a.entityId == 'x');

      expect(returns.map((a) => a.zone), [10, 5, 3]);
      expect(returns.every((a) => a.previousRank == 12), isTrue);
    });
  });

  group('first entries and re-entries, zone by zone', () {
    for (final zone in [3, 5, 10, 15, 20, 25, 50]) {
      test('Top $zone: a first entry once, then a re-entry', () {
        final plays = _Plays();
        // Fillers ranked by distinct totals: filler i has 200 - 2i plays.
        final fillers = zone + 5;
        for (var i = 0; i < fillers; i++) {
          plays.play('f${i.toString().padLeft(2, '0')}', 200 - 2 * i);
        }
        // X debuts below the zone, then climbs to exactly #zone.
        plays.play('x', 1);
        plays.play('x', 200 - 2 * (zone - 1));
        // Three fillers below pass it: X falls out of the zone.
        for (var i = zone; i < zone + 3; i++) {
          plays.play('f${i.toString().padLeft(2, '0')}', 2 * (zone + 2));
        }
        // X climbs back in.
        plays.play('x', 12);

        final result = replay.run(
          events: plays.events,
          referenceLocal: plays.now,
          thresholdEntriesFromUtc: chronicle,
          chronicleFromUtc: chronicle,
        );
        List<AllTimeAchievement> of(AllTimeAchievementType type) => [
          for (final a in result.achievements)
            if (a.entityId == 'x' && a.type == type && a.zone == zone) a,
        ];

        final first = of(AllTimeAchievementType.thresholdEntry);
        final back = of(AllTimeAchievementType.thresholdReturn);
        expect(first, hasLength(1), reason: 'first entry into the Top $zone');
        expect(first.single.rank, zone);
        expect(back, hasLength(1), reason: 're-entry into the Top $zone');
        expect(back.single.previousRank, greaterThan(zone));
        expect(back.single.rank, lessThanOrEqualTo(zone));
        expect(back.single.occurredAt.isAfter(first.single.occurredAt), isTrue);
      });
    }
  });

  group('chart days and the journey', () {
    test('day standings follow one entity, including days off the chart', () {
      final plays = _Plays()..play('a', 3);
      plays
        ..nextDay()
        ..play('b', 4)
        ..nextDay();

      final result = run(plays, standings: {'a', 'b'});

      expect(result.dayStandings['a']!.map((s) => s.rank), [1, 2]);
      expect(result.dayStandings['b']!.map((s) => s.rank), [1]);
      expect(
        result.dayStandings['a']!.first.dayStartLocal,
        DateTime(2026, 10, 5),
      );
      expect(result.daysOf('a').numberOneDays, 1);
      expect(result.daysOf('a').numberOneRun, 0);
      expect(result.daysOf('a').longestNumberOneRun, 1);
      expect(result.daysOf('a').hot100Days, 2);
    });
  });
}
