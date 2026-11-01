// SN-50 complete coverage and developing stories: every climb on the
// Career chart is recorded from the device-polish start, and one song's
// climbs on one chart in one day are one living story with a thread.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_climb.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';

import 'moment_editorial_test.dart'
    show FakeLookups, event, items, release, song;

final _start = DateTime.utc(2026, 11, 2);
final _polished = ChartMomentRules(devicePolishFromUtc: _start);

/// A local-midday instant on 3 Nov 2026, [minutes] later.
DateTime _at(int minutes) =>
    DateTime(2026, 11, 3, 12).add(Duration(minutes: minutes)).toUtc();

ChartMomentEvent _climb(
  String id, {
  required int from,
  required int to,
  required int minutes,
  int? peak,
  ChartType chartType = ChartType.songs,
  ChartMomentEventType type = ChartMomentEventType.rankRise,
  DateTime? at,
}) => event(
  type,
  entity: chartType == ChartType.songs ? song(id) : release(id),
  chartType: chartType,
  source: '$id-play-$minutes',
  at: at ?? _at(minutes),
  rank: to,
  previousRank: from,
  previousPeak: peak,
);

List<MomentStory> _compose(
  List<ChartMomentEvent> events, {
  ChartMomentRules? rules,
}) => MomentEditorialDesk(
  lookups: FakeLookups(artists: const {'artist-a': 'Name artist-a'}),
  rules: rules ?? _polished,
).compose(items(events));

void main() {
  group('Career chart recording', () {
    AllTimeReplayResult replay({DateTime? everyClimbFrom}) {
      final t0 = DateTime.utc(2026, 11, 1, 12);
      ChartRankingEvent play(String id, int minute) => ChartRankingEvent(
        entityId: id,
        qualifiedAt: t0.add(Duration(minutes: minute)),
        sourceEventId: '$id@$minute',
      );
      return const AllTimeHistoryReplay().run(
        events: [
          play('x', 0),
          play('x', 1),
          play('x', 2),
          play('y', 3),
          play('y', 4),
          play('z', 5),
          // From here on z climbs: 3 -> 3 (tie, reached later), -> 2, -> 1.
          play('z', 60 * 24 + 1),
          play('z', 60 * 24 + 2),
          play('z', 60 * 24 + 3),
        ],
        referenceLocal: DateTime(2026, 11, 3),
        achievementsFromUtc: t0,
        everyClimbFromUtc: everyClimbFrom,
      );
    }

    List<AllTimeAchievement> climbs(AllTimeReplayResult result) => [
      for (final a in result.achievements)
        if (a.type == AllTimeAchievementType.bigClimb) a,
    ];

    test('every climb is recorded from the start, +1 included', () {
      final result = replay(everyClimbFrom: DateTime.utc(2026, 11, 2));
      final found = climbs(result);
      expect(found.map((a) => (a.previousRank, a.rank)), [(3, 2), (2, 1)]);
      // The #1 is still its own achievement.
      expect(
        result.achievements.where(
          (a) =>
              a.type == AllTimeAchievementType.numberOne && a.entityId == 'z',
        ),
        hasLength(1),
      );
      // Replaying gives the same keys: saving twice is harmless.
      expect(
        climbs(
          replay(everyClimbFrom: DateTime.utc(2026, 11, 2)),
        ).map((a) => a.deduplicationKey('songs')),
        found.map((a) => a.deduplicationKey('songs')),
      );
    });

    test('nothing before the start is backfilled', () {
      expect(climbs(replay()), isEmpty);
      expect(
        climbs(replay(everyClimbFrom: DateTime.utc(2026, 12, 1))),
        isEmpty,
      );
    });

    test('ranks are unchanged by recording climbs', () {
      final off = replay();
      final on = replay(everyClimbFrom: DateTime.utc(2026, 11, 2));
      String ranks(AllTimeReplayResult r) => [
        for (final a in r.achievements)
          if (a.type != AllTimeAchievementType.bigClimb)
            '${a.type.name}:${a.entityId}:${a.rank}',
      ].join(',');
      expect(ranks(on), ranks(off));
    });
  });

  group('developing stories', () {
    test('a single small climb is one ordinary story', () {
      final stories = _compose([_climb('lg', from: 40, to: 39, minutes: 0)]);
      final story = stories.single;
      expect(story.isDeveloping, isFalse);
      expect(story.headline, contains('1 place'));
      expect(story.headline, contains('#39'));
      expect(story.status, 'CLIMBING');
    });

    test('later climbs update one story; earlier ones stay in the thread', () {
      final stories = _compose([
        _climb('lg', from: 40, to: 36, minutes: 0),
        _climb('lg', from: 36, to: 28, minutes: 30),
        _climb('lg', from: 28, to: 15, minutes: 90),
      ]);
      final story = stories.single;
      expect(story.isDeveloping, isTrue);
      expect(story.rank, 15);
      expect(story.climb, 25);
      expect(story.headline, contains('#15'));
      expect(story.headline, contains('25 places'));
      expect(story.headline, contains('#40'));
      expect(story.occurredAt, _at(90));
      expect(story.updates.map((u) => u.text), [
        'Song lg climbs 4 places to #36 on the Sonus Hot 100.',
        'UPDATE: Song lg climbs another 8 places to #28.',
        'UPDATE: Song lg climbs another 13 places to #15.',
      ]);
      expect(story.body, contains('Updated 2 times'));
    });

    test('a slip is told as it happened, never added up', () {
      // #40 -> #36 -> #28, slips to #32, rebounds to #27.
      final story = _compose([
        _climb('lg', from: 40, to: 36, minutes: 0),
        _climb('lg', from: 36, to: 28, minutes: 30),
        _climb('lg', from: 32, to: 27, minutes: 60),
      ]).single;
      expect(
        story.updates.last.text,
        'UPDATE: After slipping to #32, Song lg rebounds 5 places to #27.',
      );
      expect(story.headline, contains('After slipping to #32'));
      expect(story.headline, contains('up 13 places from #40'));
      expect(story.climb, 13);
    });

    test('net movement is the real distance from where it began', () {
      // #40 -> #36, slips to #45, rebounds to #41: one place below #40.
      final story = _compose([
        _climb('lg', from: 40, to: 36, minutes: 0),
        _climb('lg', from: 45, to: 41, minutes: 60),
      ]).single;
      expect(story.headline, contains('rebounds 4 places to #41'));
      expect(story.headline, isNot(contains(' up ')));
      expect(story.climb, isNull);
      expect(story.body, contains('best in this story was #36'));
    });

    test('a new career high is named', () {
      final story = _compose([
        _climb('lg', from: 30, to: 25, minutes: 0, peak: 22),
        _climb('lg', from: 25, to: 18, minutes: 5, peak: 22),
      ]).single;
      expect(story.headline, contains('#18'));
      expect(story.headline.toLowerCase(), contains('career high'));
      expect(story.updates.last.text, endsWith('a new career high.'));
    });

    test('a debut followed by climbs keeps the debut as its own story', () {
      final stories = _compose([
        event(
          ChartMomentEventType.debut,
          entity: song('lg'),
          source: 'lg-debut',
          at: _at(0),
          rank: 42,
        ),
        _climb('lg', from: 42, to: 40, minutes: 10),
        _climb('lg', from: 40, to: 33, minutes: 20),
      ]);
      expect(stories.map((s) => s.family).toSet(), {
        MomentFamily.songDebut,
        MomentFamily.songBigClimb,
      });
      expect(stories.firstWhere((s) => s.isDeveloping).updates, hasLength(2));
    });

    test('a #1 reached by a climb is its own story beside the developing '
        'one', () {
      final stories = _compose([
        _climb('lg', from: 5, to: 3, minutes: 0),
        _climb('lg', from: 3, to: 1, minutes: 10),
        event(
          ChartMomentEventType.firstNumberOne,
          entity: song('lg'),
          source: 'lg-play-10',
          at: _at(10),
          rank: 1,
          previousRank: 3,
        ),
      ]);
      expect(
        stories.where((s) => s.family == MomentFamily.songFirstNumberOne),
        hasLength(1),
      );
      final developing = stories.singleWhere((s) => s.isDeveloping);
      expect(developing.rank, 1);
      expect(developing.updates, hasLength(2));
    });

    test('songs, charts and days never share a story', () {
      final stories = _compose([
        _climb('a', from: 40, to: 36, minutes: 0),
        _climb('a', from: 36, to: 30, minutes: 5),
        _climb('b', from: 50, to: 45, minutes: 1),
        _climb('b', from: 45, to: 44, minutes: 6),
        // Song a on Bubbling Under the same day: another chart.
        _climb('a', from: 150, to: 140, minutes: 2),
        // Song a the next day: another story.
        _climb('a', from: 33, to: 31, minutes: 60 * 24),
        // A release with the same id on Albums & EPs.
        _climb('a', from: 20, to: 18, minutes: 3, chartType: ChartType.albums),
      ]);
      final developing = stories.where((s) => s.isDeveloping).toList();
      expect(developing, hasLength(2));
      expect(developing.map((s) => s.item.entity.entityId).toSet(), {'a', 'b'});
      expect(stories, hasLength(5));
    });

    test('the same events composed again make the same stories', () {
      final events = [
        _climb('lg', from: 40, to: 36, minutes: 0),
        _climb('lg', from: 36, to: 28, minutes: 30),
      ];
      final first = _compose(events);
      final again = _compose([...events, ...events]);
      expect(again.map((s) => s.id), first.map((s) => s.id));
      expect(again.map((s) => s.headline), first.map((s) => s.headline));
      expect(
        again.single.updates.map((u) => u.eventId),
        first.single.updates.map((u) => u.eventId),
      );
    });

    test('a move into the Hot 100 is an arrival, not a climb of places', () {
      final story = _compose([
        _climb('lg', from: 104, to: 96, minutes: 0),
      ]).single;
      expect(story.family, MomentFamily.songHot100Breakthrough);
      expect(story.headline, isNot(contains('8 places')));
      expect(story.climb, isNull);
    });

    test('Albums & EPs climbs have release wording', () {
      final stories = _compose([
        _climb('r', from: 30, to: 27, minutes: 0, chartType: ChartType.albums),
        _climb('r', from: 27, to: 26, minutes: 5, chartType: ChartType.albums),
        _climb('s', from: 60, to: 58, minutes: 1, chartType: ChartType.albums),
      ]);
      final single = stories.singleWhere((s) => !s.isDeveloping);
      expect(single.family, MomentFamily.releaseClimb);
      expect(single.headline, contains('2 places'));
      expect(single.headline, contains('Albums & EPs'));
      final developing = stories.singleWhere((s) => s.isDeveloping);
      expect(developing.family, MomentFamily.releaseClimb);
      expect(developing.updates.last.text, contains('another 1 place'));
    });

    test('both publishers write developing stories', () {
      final publishers = <MomentPublisher>{};
      for (var i = 0; i < 12; i++) {
        final story = _compose([
          _climb('s$i', from: 40, to: 36, minutes: 0),
          _climb('s$i', from: 36, to: 30, minutes: 5),
        ]).single;
        publishers.add(story.publisher);
        expect(story.headline, contains('#30'));
      }
      expect(publishers, MomentPublisher.values.toSet());
    });

    test('before the start, climbs keep their first telling', () {
      final before = DateTime.utc(2026, 10, 28, 12);
      final events = [
        _climb('lg', from: 40, to: 20, minutes: 0, at: before),
        _climb(
          'lg',
          from: 20,
          to: 4,
          minutes: 5,
          at: before.add(const Duration(minutes: 5)),
        ),
      ];
      final legacy = _compose(events, rules: ChartMomentRules.legacy);
      final polishedRules = _compose(events);
      expect(polishedRules.any((s) => s.isDeveloping), isFalse);
      expect(
        polishedRules.map((s) => s.headline),
        legacy.map((s) => s.headline),
      );
    });

    test('high volume: 150 songs climbing 4 times each stay 150 stories', () {
      final events = [
        for (var s = 0; s < 150; s++)
          for (var step = 0; step < 4; step++)
            _climb(
              'v$s',
              from: 190 - step * 10,
              to: 180 - step * 10,
              minutes: s + step * 150,
            ),
      ];
      final watch = Stopwatch()..start();
      final stories = _compose(events);
      watch.stop();
      expect(stories, hasLength(150));
      expect(stories.every((s) => s.updates.length == 4), isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('placesText reads naturally', () {
      expect(MomentClimb.placesText(1), '1 place');
      expect(MomentClimb.placesText(25), '25 places');
    });
  });
}
