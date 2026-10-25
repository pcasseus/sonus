import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

/// A UTC instant [minutes] after a fixed Monday noon.
DateTime at(int minutes) =>
    DateTime.utc(2026, 10, 5, 12).add(Duration(minutes: minutes));

class _Plays {
  final List<ChartRankingEvent> events = [];
  var _clock = 0;
  var _ids = 0;

  /// [times] plays of [entity], one minute apart.
  void play(String entity, [int times = 1]) {
    for (var i = 0; i < times; i++) {
      events.add(
        ChartRankingEvent(
          entityId: entity,
          qualifiedAt: at(_clock++),
          sourceEventId: 'play-${++_ids}',
        ),
      );
    }
  }

  void wait(Duration duration) => _clock += duration.inMinutes;

  DateTime get now => at(_clock).toLocal();
}

void main() {
  const replay = AllTimeHistoryReplay();

  List<AllTimeAchievement> achievements(
    _Plays plays, {
    String? entity,
    DateTime? from,
  }) => replay
      .run(
        events: plays.events,
        referenceLocal: plays.now,
        achievementsFromUtc: from,
      )
      .achievements
      .where((a) => entity == null || a.entityId == entity)
      .toList();

  group('achievements', () {
    test('the first song debuts at #1, which outranks the debut', () {
      final plays = _Plays()..play('a');

      final result = achievements(plays);

      expect(result.single.type, AllTimeAchievementType.numberOne);
      expect(result.single.rank, 1);
    });

    test('a debut inside the Top 100 is one story, not two', () {
      final plays = _Plays()
        ..play('leader', 3)
        ..play('new');

      final result = achievements(plays, entity: 'new');

      expect(result.single.type, AllTimeAchievementType.debut);
      expect(result.single.rank, 2);
    });

    test('debut below 100, then the Top 100 as its own story', () {
      final plays = _Plays();
      for (var i = 0; i < 120; i++) {
        plays.play('filler-${i.toString().padLeft(3, '0')}', i < 20 ? 5 : 2);
      }
      plays.play('climber');
      plays.play('climber', 2);

      final types = [
        for (final a in achievements(plays, entity: 'climber')) a.type,
      ];
      expect(types, [
        AllTimeAchievementType.debut,
        AllTimeAchievementType.top100Entry,
      ]);
    });

    test('taking #1, losing it, and returning are separate stories', () {
      final plays = _Plays()
        ..play('a', 2)
        ..play('b', 3) // b passes a and takes #1.
        ..play('a', 2); // a back to #1.

      final aTypes = [for (final x in achievements(plays, entity: 'a')) x.type];
      final bTypes = [for (final x in achievements(plays, entity: 'b')) x.type];

      expect(aTypes, [
        AllTimeAchievementType.numberOne,
        AllTimeAchievementType.returnsToNumberOne,
      ]);
      expect(bTypes, contains(AllTimeAchievementType.numberOne));
    });

    test('a re-entry needs a real absence; churn is not a story', () {
      final plays = _Plays()
        ..play('leader', 10)
        ..play('target');
      String pusher(int i) => 'push-${i.toString().padLeft(3, '0')}';
      // 200 others push target out of the Top 200.
      for (var i = 0; i < 200; i++) {
        plays.play(pusher(i), 2);
      }
      plays.play('target', 2); // Back within minutes: churn.
      expect(
        achievements(plays, entity: 'target').map((a) => a.type),
        isNot(contains(AllTimeAchievementType.reentry)),
      );

      // Out again, and back over a week later: a re-entry.
      for (var i = 0; i < 200; i++) {
        plays.play(pusher(i), 2);
      }
      plays.wait(const Duration(days: 8));
      plays.play('target', 2);

      final reentries = achievements(
        plays,
        entity: 'target',
      ).where((a) => a.type == AllTimeAchievementType.reentry);
      expect(reentries, hasLength(1));
    });

    test('new peaks only when a higher zone is reached', () {
      final plays = _Plays();
      for (var i = 0; i < 60; i++) {
        plays.play('f-${i.toString().padLeft(2, '0')}', 10 - (i ~/ 7));
      }
      // Climbs from the bottom one play at a time.
      for (var i = 0; i < 12; i++) {
        plays.play('rise');
      }

      final peaks = achievements(
        plays,
        entity: 'rise',
      ).where((a) => a.type == AllTimeAchievementType.newPeak).toList();

      expect(peaks, isNotEmpty);
      final zones = [for (final peak in peaks) peak.zone];
      expect(zones.toSet().length, zones.length, reason: 'one per zone');
      for (final peak in peaks) {
        expect(peak.rank, lessThanOrEqualTo(peak.zone!));
        expect(peak.previousPeakRank, greaterThan(peak.zone!));
      }
    });

    test('nothing before the activation time becomes a story', () {
      final plays = _Plays()..play('old', 3);
      final activation = at(10);
      plays.wait(const Duration(minutes: 20));
      plays.play('new', 1);

      final result = achievements(plays, from: activation);

      expect(result.map((a) => a.entityId), ['new']);
    });

    test('the same achievement has the same key on every replay', () {
      final plays = _Plays()
        ..play('a', 2)
        ..play('b', 3)
        ..play('a', 2);

      List<String> keys(DateTime? from) => [
        for (final a in achievements(plays, from: from))
          a.deduplicationKey('songs'),
      ];

      final full = keys(null);
      expect(full.toSet().length, full.length, reason: 'all distinct');
      expect(keys(null), full, reason: 'replaying again changes nothing');
      // A later window yields a subset with identical keys.
      expect(full, containsAll(keys(at(3))));
    });
  });

  group('weeks in zones', () {
    test('counted once per completed week, cumulatively', () {
      final plays = _Plays()
        ..play('a', 3)
        ..play('b', 2);
      // Three full weeks later, with no more listening.
      plays.wait(const Duration(days: 21));

      final result = replay.run(
        events: plays.events,
        referenceLocal: plays.now,
      );

      expect(result.observedWeeks, greaterThanOrEqualTo(3));
      final weeks = result.observedWeeks;
      final a = result.zonesOf('a');
      final b = result.zonesOf('b');
      expect(a.weeksIn(3), weeks);
      expect(a.weeksIn(200), weeks);
      expect(b.weeksIn(3), weeks);
      expect(a.bestZone, 3);
      expect(result.zonesOf('nobody').isEmpty, isTrue);
    });

    test('the current, unfinished week is not counted', () {
      final plays = _Plays()..play('a');

      final result = replay.run(
        events: plays.events,
        referenceLocal: plays.now,
      );

      expect(result.observedWeeks, 0);
      expect(result.zonesOf('a').isEmpty, isTrue);
    });
  });

  test('standings agree with the accepted all-time ranking', () {
    final plays = _Plays();
    for (var i = 0; i < 40; i++) {
      plays.play('e-${i % 13}', 1 + (i * 7) % 5);
    }

    final engine = const AllTimeChartRankingEngine().rank(
      events: plays.events,
      comparisonStartUtc: at(0),
    );
    final peaks = {for (final e in engine) e.entityId: e.peakRank};
    final replayed = replay.run(
      events: plays.events,
      referenceLocal: plays.now,
    );

    // Every first-#1 the replay sees is an entity whose accepted peak is 1.
    for (final a in replayed.achievements) {
      if (a.type == AllTimeAchievementType.numberOne) {
        expect(peaks[a.entityId], 1);
      }
    }
  });
}
