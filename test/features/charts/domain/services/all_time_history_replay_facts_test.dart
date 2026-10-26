// SN-45: the facts Moments need, recorded by the replay only when they
// really happened.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';

void main() {
  const replay = AllTimeHistoryReplay();
  final start = DateTime.utc(2026, 10, 20, 9);
  var minute = 0;

  ChartRankingEvent play(String id) => ChartRankingEvent(
    entityId: id,
    qualifiedAt: start.add(Duration(minutes: minute++)),
    sourceEventId: 'play-$minute',
  );

  setUp(() => minute = 0);

  List<AllTimeAchievement> run(
    List<ChartRankingEvent> events, {
    List<int> milestones = const [],
    String? Function(String)? groupOf,
    DateTime? from,
  }) => replay
      .run(
        events: events,
        referenceLocal: DateTime(2026, 10, 27),
        streamMilestones: milestones,
        groupOf: groupOf,
        achievementsFromUtc: from,
      )
      .achievements;

  test('a #1 names the entity it displaced, verified by the standings', () {
    final achievements = run([
      play('a'),
      play('a'),
      play('b'),
      play('b'),
      play('b'),
    ]);

    final takeover = achievements.singleWhere(
      (a) => a.type == AllTimeAchievementType.numberOne && a.entityId == 'b',
    );
    expect(takeover.displacedEntityId, 'a');
    expect(takeover.previousRank, 2);

    final first = achievements.singleWhere(
      (a) => a.type == AllTimeAchievementType.numberOne && a.entityId == 'a',
    );
    expect(first.displacedEntityId, isNull, reason: 'nobody was #1 before');
  });

  test('stream milestones fire exactly when reached, once', () {
    final achievements = run(
      [for (var i = 0; i < 30; i++) play('a')],
      milestones: [10, 25],
    );

    final milestones = [
      for (final a in achievements)
        if (a.type == AllTimeAchievementType.streamMilestone) a.milestone,
    ];
    expect(milestones, [10, 25]);
  });

  test('career ordinals count each artist\'s songs, including the past', () {
    String? artistOf(String song) => song.split(':').first;
    final achievements = run([
      play('x:one'),
      play('x:one'),
      // x:two reaches #1 on its own later.
      play('x:two'),
      play('x:two'),
      play('x:two'),
      play('y:hit'),
      play('y:hit'),
      play('y:hit'),
      play('y:hit'),
    ], groupOf: artistOf);

    List<(String, int?)> career(AllTimeAchievementType type) => [
      for (final a in achievements)
        if (a.type == type) (a.entityId, a.milestone),
    ];

    expect(career(AllTimeAchievementType.careerNumberOne), [
      ('x:one', 1),
      ('x:two', 2),
      ('y:hit', 1),
    ]);
    expect(career(AllTimeAchievementType.careerTop10), [
      ('x:one', 1),
      ('x:two', 2),
      ('y:hit', 1),
    ]);
  });

  test('ordinals before the story window still count, unannounced', () {
    String? artistOf(String song) => song.split(':').first;
    final events = [play('x:old'), play('x:new'), play('x:new')];
    final cutoff = events[1].qualifiedAt;

    final achievements = run(events, groupOf: artistOf, from: cutoff);

    final career = achievements
        .where((a) => a.type == AllTimeAchievementType.careerNumberOne)
        .toList();
    expect(career.single.entityId, 'x:new');
    expect(career.single.milestone, 2, reason: 'x:old was #1 first');
  });

  test('without a group nothing counts as a career fact', () {
    final achievements = run([play('a'), play('a')]);
    expect(
      achievements.where(
        (a) =>
            a.type == AllTimeAchievementType.careerNumberOne ||
            a.type == AllTimeAchievementType.careerTop10 ||
            a.type == AllTimeAchievementType.careerTop100,
      ),
      isEmpty,
    );
  });
}
