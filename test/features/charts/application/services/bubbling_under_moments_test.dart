// SN-50 BUG-04: Bubbling Under movement and Hot 100 arrivals. Made-up
// finalized weeks go through the real weekly detectors, the real Moment
// store, the real feed aggregator and the real editorial desk.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_achievement_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_finalized_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_longevity_calculator.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_milestone_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

class _Lookups implements MomentLookups {
  @override
  String? artistName(String artistId) => 'Artist $artistId';

  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;

  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;

  @override
  List<String> featuredOf(String songId) => const [];

  @override
  String? artistIdNamed(String name) => null;

  @override
  String? songCover(String songId) => '/covers/$songId.jpg';

  @override
  String? releaseCover(String albumId) => '/covers/$albumId.jpg';

  @override
  String? currentSongCover(String songId) => songCover(songId);

  @override
  String? currentReleaseCover(String albumId) => releaseCover(albumId);

  @override
  String? artistPortrait(String artistId) => '/portraits/$artistId.jpg';
}

ChartEntitySnapshot _song(String id) => ChartEntitySnapshot(
  entityId: id,
  title: 'Song $id',
  artistId: 'artist-$id',
  artistName: 'Artist $id',
  albumTitle: 'Album $id',
);

/// Finalizes one song week at a time, as the finalization service does.
class _Weeks {
  _Weeks(this._start);

  DateTime _start;
  final List<ChartSnapshot> history = [];

  DateTime get nextStart => _start;

  (DateTime, List<ChartMomentEvent>) week(Map<ChartEntitySnapshot, int> ranks) {
    final start = _start;
    final end = start.add(const Duration(days: 7));
    final previous = history.isNotEmpty && history.last.weekEndUtc == start
        ? history.last
        : null;
    final previousRanks = {
      for (final entry in previous?.entries ?? const <ChartEntry>[])
        entry.entity.entityId: entry.rank,
    };
    final peaks = <String, int>{};
    for (final snapshot in history) {
      for (final entry in snapshot.entries) {
        final id = entry.entity.entityId;
        if (entry.peakRank < (peaks[id] ?? 999)) peaks[id] = entry.peakRank;
      }
    }
    final snapshot = ChartSnapshot(
      id: 'chart_songs_${start.millisecondsSinceEpoch}',
      chartType: ChartType.songs,
      weekStartUtc: start,
      weekEndUtc: end,
      finalizedAt: end,
      entries: [
        for (final MapEntry(key: entity, value: rank) in ranks.entries)
          ChartEntry(
            entity: entity,
            rank: rank,
            qualifiedStreamCount: 300 - rank,
            lastQualifiedAt: end,
            previousFinalRank: previousRanks[entity.entityId],
            peakRank: rank < (peaks[entity.entityId] ?? 999)
                ? rank
                : peaks[entity.entityId]!,
            peakAchievedAt: end,
            weeksOnChart: 1,
            movement: ChartMovement.same,
          ),
      ],
    );
    final events = [
      ...const ChartMomentFinalizedDetector().detect(
        snapshot: snapshot,
        history: history,
        createdAt: end,
      ),
      ...const ChartMomentArtistAchievementDetector().detect(
        snapshot: snapshot,
        history: history,
        createdAt: end,
      ),
    ];
    // Longevity milestones, as finalization records them (the fifth Hot
    // 100 week is the evidence for a notable exit).
    final baseline =
        previous ??
        ChartSnapshot(
          id: 'baseline',
          chartType: ChartType.songs,
          weekStartUtc: start.subtract(const Duration(days: 7)),
          weekEndUtc: start,
          finalizedAt: start,
          entries: const [],
        );
    const longevity = ChartMomentLongevityCalculator();
    for (final entry in snapshot.entries) {
      events.addAll(
        const ChartMomentMilestoneDetector().detect(
          snapshot: snapshot,
          entry: entry,
          previousLongevity: longevity.calculate(
            entityId: entry.entity.entityId,
            snapshot: baseline,
            history: history,
          ),
          currentLongevity: longevity.calculate(
            entityId: entry.entity.entityId,
            snapshot: snapshot,
            history: history,
          ),
          previousLifetimeStreams: 0,
          currentLifetimeStreams: 0,
          createdAt: end,
        ),
      );
    }
    history.add(snapshot);
    _start = end;
    return (start, events);
  }
}

final _from = DateTime.utc(2026, 11, 1);
final _activated = ChartMomentRules(activatedAtUtc: _from);

// The addendum's songs.
final _up = _song('up'); // #171 -> #139, within Bubbling Under
final _down = _song('down'); // #122 -> #168, within Bubbling Under
final _arrival = _song('arrival'); // #124 -> #87, first Hot 100 entry
final _back = _song('back'); // #80, #112, then #90: a Hot 100 re-entry
final _drop = _song('drop'); // #94 -> #121, into Bubbling Under
final _fresh = _song('fresh'); // a first debut at #176
final _deep = _song('deep'); // #130, off, then #95: first Hot 100 entry
final _return = _song('return'); // #140, off, then #150

List<Map<ChartEntitySnapshot, int>> get _songWeeks => [
  {_back: 80, _drop: 94, _down: 122, _arrival: 150, _deep: 130, _return: 140},
  {_drop: 94, _back: 112, _down: 122, _arrival: 124, _up: 171},
  {
    _arrival: 87,
    _back: 90,
    _deep: 95,
    _drop: 121,
    _up: 139,
    _return: 150,
    _down: 168,
    _fresh: 176,
  },
];

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SqliteChartMomentRepository moments;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await database.database;
    moments = SqliteChartMomentRepository(database);
  });

  tearDown(() => database.close());

  Future<DateTime> publish(
    DateTime from, [
    List<Map<ChartEntitySnapshot, int>>? songWeeks,
  ]) async {
    final weeks = _Weeks(from);
    late DateTime last;
    for (final ranks in songWeeks ?? _songWeeks) {
      final (start, events) = weeks.week(ranks);
      last = start;
      await moments.publishFinalizedForWeek(
        chartType: ChartType.songs,
        weekStartUtc: start,
        events: events,
      );
    }
    return last;
  }

  Future<List<GatedMoment>> gated(ChartMomentRules rules) async =>
      MomentEditorialDesk(lookups: _Lookups(), rules: rules).copyGated(
        const ChartMomentFeedAggregator().aggregate(await moments.getRecent()),
      );

  Future<List<MomentStory>> stories(ChartMomentRules rules) async =>
      MomentEditorialDesk(lookups: _Lookups(), rules: rules).compose(
        const ChartMomentFeedAggregator().aggregate(await moments.getRecent()),
      );

  List<MomentStory> of(
    List<MomentStory> all,
    ChartEntitySnapshot song,
    DateTime week,
  ) => [
    for (final story in all.reversed)
      if (story.item.entity.entityId == song.entityId &&
          story.item.subjectType != ChartMomentFeedSubjectType.artist &&
          story.item.weekStartUtc == week)
        story,
  ];

  group('with the SN-50 rules', () {
    late List<MomentStory> all;
    late DateTime week3;

    setUp(() async {
      week3 = await publish(_from);
      all = await stories(_activated);
    });

    List<MomentFamily> families(ChartEntitySnapshot song) => [
      for (final story in of(all, song, week3)) story.family,
    ];

    test('a first debut at #176 is a guaranteed Bubbling Under story', () {
      final story = of(all, _fresh, week3).single;
      expect(story.family, MomentFamily.songBubblingUnderDebut);
      expect(story.headline, contains('Bubbling Under'));
      expect(story.headline, isNot(contains('Hot 100')));
    });

    test('#124 to #87 is a first Hot 100 entry, never a 37-place climb', () {
      expect(families(_arrival), [MomentFamily.songHot100Breakthrough]);
      final story = of(all, _arrival, week3).single;
      expect(
        MomentStoryPlanner.misleadingArrivalVariants,
        isNot(contains(story.variantId)),
      );
      expect(story.headline, contains('Hot 100'));
      for (final text in [story.headline, story.body ?? '']) {
        expect(text, isNot(contains('37')));
      }
    });

    test('#112 to #90 after an earlier Hot 100 run is a Hot 100 re-entry', () {
      expect(families(_back), [MomentFamily.songReentry]);
      final story = of(all, _back, week3).single;
      expect(story.id, endsWith('#hot-100'));
      expect(story.headline, isNot(contains('Bubbling')));
      expect(story.headline, isNot(contains('22')));
    });

    test('back on the chart at #95 after only Bubbling Under weeks is a '
        'first Hot 100 entry, without "from Bubbling Under" wording', () {
      expect(families(_deep), [MomentFamily.songHot100Breakthrough]);
      final story = of(all, _deep, week3).single;
      expect(
        MomentStoryPlanner.fromBubblingUnderVariants,
        isNot(contains(story.variantId)),
      );
      expect(story.headline, isNot(contains('Bubbling')));
      expect(story.headline, isNot(contains('re-enters')));
    });

    test(
      'a return to Bubbling Under is a re-entry there, not on the Hot 100',
      () {
        expect(families(_return), [MomentFamily.songReentry]);
        expect(
          of(all, _return, week3).single.headline,
          isNot(contains('Hot 100')),
        );
      },
    );

    test('#171 to #139 is told as the biggest gainer on Bubbling Under; '
        'cross-chart moves do not compete for it', () {
      expect(families(_up), [MomentFamily.songBiggestGainer]);
      expect(of(all, _up, week3).single.headline, isNot(contains('Hot 100')));
    });

    test('a fall within Bubbling Under and a drop out of the Hot 100 have no '
        'approved copy yet, so they publish nothing', () {
      expect(families(_down), isEmpty);
      expect(families(_drop), isEmpty);
    });

    test(
      'composing again, or finalizing a week again, changes nothing',
      () async {
        final again = await stories(_activated);
        expect(
          [for (final story in again) '${story.id}|${story.headline}'],
          [for (final story in all) '${story.id}|${story.headline}'],
        );

        final replay = _Weeks(_from);
        for (final ranks in _songWeeks) {
          final (start, events) = replay.week(ranks);
          expect(
            await moments.publishFinalizedForWeek(
              chartType: ChartType.songs,
              weekStartUtc: start,
              events: events,
            ),
            isFalse,
          );
        }
      },
    );
  });

  test('weeks before activation keep their earlier stories', () async {
    final before = DateTime.utc(2026, 8, 16);
    await publish(before);
    final legacy = await stories(ChartMomentRules.legacy);
    final activated = await stories(_activated);

    expect(
      [for (final story in activated) '${story.id}|${story.headline}'],
      [for (final story in legacy) '${story.id}|${story.headline}'],
    );
  });

  group('approved BUG-04 rules (rises 20+, falls 30+, notable exits)', () {
    final a = _song('a'); // #171 -> #139: +32
    final b = _song('b'); // #140 -> #121: +19
    final c = _song('c'); // #122 -> #168: -46
    final d = _song('d'); // #131 -> #160: -29
    final climbers = [for (var i = 1; i <= 5; i++) _song('e$i')];
    List<Map<ChartEntitySnapshot, int>> moves() => [
      {
        a: 171,
        b: 140,
        c: 122,
        d: 131,
        for (final (i, song) in climbers.indexed) song: 190 - i,
      },
      {
        a: 139,
        b: 121,
        c: 168,
        d: 160,
        climbers[0]: 160,
        climbers[1]: 165,
        climbers[2]: 150,
        climbers[3]: 155,
        climbers[4]: 162,
      },
    ];

    List<MomentFamily> families(
      List<MomentStory> all,
      ChartEntitySnapshot song,
      DateTime week,
    ) => [for (final story in of(all, song, week)) story.family];

    test(
      'every Bubbling Under climb of 20+ places is a story; +19 is not',
      () async {
        final week2 = await publish(_from, moves());
        final all = await stories(_activated);

        expect(families(all, a, week2), [MomentFamily.songBigClimb]);
        expect(families(all, b, week2), isEmpty);
        final story = of(all, a, week2).single;
        expect(story.id, endsWith('#bu-climb'));
        expect(story.headline, isNot(contains('Hot 100')));
      },
    );

    test('five songs climbing 20+ in one week are five stories, outside '
        'the daily cap', () async {
      final week2 = await publish(_from, moves());
      final all = await stories(_activated);

      final told = [for (final song in climbers) ...families(all, song, week2)];
      expect(told, hasLength(5));
      // The week's biggest gainer tells its own climb once.
      expect(
        told.where((family) => family == MomentFamily.songBiggestGainer),
        hasLength(1),
      );
      expect(
        told.where((family) => family == MomentFamily.songBigClimb),
        hasLength(4),
      );
    });

    test('a fall of 30+ within Bubbling Under is detected but held for '
        'copy approval; -29 is not detected', () async {
      final week2 = await publish(_from, moves());
      final all = await stories(_activated);
      final held = await gated(_activated);

      expect(families(all, c, week2), isEmpty);
      expect(families(all, d, week2), isEmpty);
      expect(
        [
          for (final moment in held)
            if (moment.kind == GatedMomentKind.bubblingUnderFall)
              moment.event.entity.entityId,
        ],
        ['c'],
      );
    });

    test('a Hot 100 exit into Bubbling Under is held for copy approval '
        'only after a Top 40 peak or five Hot 100 weeks', () async {
      final peak35 = _song('peak-35');
      final fiveWeeks = _song('five-weeks');
      final fourWeeks = _song('four-weeks');
      final last = await publish(_from, [
        {fiveWeeks: 60},
        {fiveWeeks: 70, fourWeeks: 60},
        {fiveWeeks: 80, fourWeeks: 70},
        {fiveWeeks: 90, fourWeeks: 80, peak35: 35},
        {fiveWeeks: 94, fourWeeks: 94, peak35: 94},
        {fiveWeeks: 121, fourWeeks: 121, peak35: 121},
      ]);
      final held = await gated(_activated);
      final exits = {
        for (final moment in held)
          if (moment.kind == GatedMomentKind.notableHot100Exit)
            moment.event.entity.entityId: moment,
      };

      expect(exits.keys, unorderedEquals(['peak-35', 'five-weeks']));
      expect(exits.values.every((m) => m.event.weekStartUtc == last), isTrue);
      expect(exits.values.every((m) => m.id.endsWith('#hot-100-exit')), isTrue);
      // A move across the chart boundary is never a Bubbling Under fall.
      expect(
        held.where((m) => m.kind == GatedMomentKind.bubblingUnderFall),
        isEmpty,
      );
      // Nothing about an exit is published.
      final all = await stories(_activated);
      for (final song in [peak35, fiveWeeks, fourWeeks]) {
        expect(of(all, song, last), isEmpty);
      }
    });

    test('detection is stable: composing again gives the same stories and '
        'held items', () async {
      await publish(_from, moves());
      final first = await stories(_activated);
      final firstHeld = await gated(_activated);

      expect(
        [for (final story in await stories(_activated)) story.id],
        [for (final story in first) story.id],
      );
      expect(
        [for (final moment in await gated(_activated)) moment.id],
        [for (final moment in firstHeld) moment.id],
      );
      expect({for (final story in first) story.id}, hasLength(first.length));
    });

    test(
      'weeks before activation publish and hold exactly what they did',
      () async {
        await publish(DateTime.utc(2026, 8, 16), moves());

        expect(
          [
            for (final story in await stories(_activated))
              '${story.id}|${story.headline}',
          ],
          [
            for (final story in await stories(ChartMomentRules.legacy))
              '${story.id}|${story.headline}',
          ],
        );
        expect(await gated(_activated), isEmpty);
      },
    );
  });
}
