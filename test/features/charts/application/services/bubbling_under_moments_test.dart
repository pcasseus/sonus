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
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
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
  List<String> guestsOf(String songId) => const [];

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

  (DateTime, List<ChartMomentEvent>) week(
    Map<ChartEntitySnapshot, int> ranks, {
    Map<ChartEntitySnapshot, int> streams = const {},
  }) {
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
            qualifiedStreamCount: streams[entity] ?? 300 - rank,
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
    List<Map<ChartEntitySnapshot, int>> streams = const [],
  ]) async {
    final weeks = _Weeks(from);
    late DateTime last;
    for (final (i, ranks) in (songWeeks ?? _songWeeks).indexed) {
      final (start, events) = weeks.week(
        ranks,
        streams: i < streams.length ? streams[i] : const {},
      );
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

    test('a 46-place fall within Bubbling Under is a story (Batch 5); a drop '
        'out of the Hot 100 without a Top 40 peak or five weeks is not', () {
      expect(families(_down), [MomentFamily.songBubblingUnderFall]);
      expect(of(all, _down, week3).single.id, endsWith('#bu-fall'));
      // #94, #94, then #121: a #94 peak and two Hot 100 weeks.
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

    test('a fall of 30+ within Bubbling Under is told under its held id '
        '(Batch 5); -29 is not', () async {
      final week2 = await publish(_from, moves());
      final all = await stories(_activated);

      expect(families(all, c, week2), [MomentFamily.songBubblingUnderFall]);
      final story = of(all, c, week2).single;
      expect(story.id, endsWith('#bu-fall'));
      expect(story.headline, contains('Bubbling Under'));
      expect(story.headline, isNot(contains('Hot 100')));
      expect(families(all, d, week2), isEmpty);
      expect(await gated(_activated), isEmpty);
    });

    test('a Hot 100 exit into Bubbling Under is told (Batch 5) only after a '
        'Top 40 peak or five Hot 100 weeks', () async {
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
      final all = await stories(_activated);
      final exits = {
        for (final song in [peak35, fiveWeeks, fourWeeks])
          for (final story in of(all, song, last))
            if (story.family == MomentFamily.songHot100Exit)
              song.entityId: story,
      };

      expect(exits.keys, unorderedEquals(['peak-35', 'five-weeks']));
      expect(exits.values.every((s) => s.id.endsWith('#hot-100-exit')), isTrue);
      // A move across the chart boundary is never a Bubbling Under fall.
      for (final song in [peak35, fiveWeeks, fourWeeks]) {
        expect(
          families(all, song, last),
          isNot(contains(MomentFamily.songBubblingUnderFall)),
        );
      }
      // Only a verified Top 40 peak is ever named.
      const peakLines = {'song-exit-d3', 'song-exit-d4', 'song-exit-p3'};
      expect(peakLines, isNot(contains(exits['five-weeks']!.variantId)));
      for (final story in exits.values) {
        expect(story.headline, isNot(contains('27')));
        expect(story.headline, contains('Bubbling Under'));
      }
      expect(await gated(_activated), isEmpty);
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

  group('SN-50 chart jumps (approved CJ-001 to CJ-041)', () {
    List<MomentStory> jumps(List<MomentStory> all) => [
      for (final story in all)
        if (story.family == MomentFamily.songHot100MajorJump ||
            story.family == MomentFamily.songHot100ClimbRun)
          story,
    ];
    final streamSentence = RegExp('qualified streams', caseSensitive: false);

    test('a Hot 100 climb of 25+ places is a PulsePop jump story under its '
        'planned id; +24 is not', () async {
      final jump = _song('jump');
      final small = _song('small');
      // The week's biggest gainer keeps its own story (rule 4).
      final gainer = _song('gainer');
      // An earlier week inside the zones, so the jump enters no zone for
      // the first time (a first zone story would tell the move).
      final last = await publish(_from, [
        {jump: 45},
        {jump: 80, small: 75, gainer: 99},
        {jump: 50, small: 51, gainer: 20},
      ]);
      final all = await stories(_activated);

      final story = of(all, jump, last).singleWhere(
        (story) => story.family == MomentFamily.songHot100MajorJump,
      );
      expect(story.id, endsWith('#hot-100-jump'));
      expect(story.publisher, MomentPublisher.pulsePop);
      expect(story.variantId, startsWith('song-jump-p'));
      expect(story.headline, contains('#50'));
      expect(story.headline, isNot(contains('stream')));
      expect(story.facts.jump!.placesGained, 30);
      // Streams are 300 - rank in this fixture: 250 this week, 220 last.
      expect(story.body, contains(streamSentence));
      expect(story.body, contains('250'));
      expect(story.body, contains('30'));
      expect(jumps(of(all, small, last)), isEmpty);
      expect(
        of(all, gainer, last).map((story) => story.family),
        contains(MomentFamily.songBiggestGainer),
      );
      expect(jumps(of(all, gainer, last)), isEmpty);
    });

    test('three climbing weeks worth 30+ places are a Sonus Daily run '
        'story; positions and streams stay separate facts', () async {
      final climber = _song('climber');
      final last = await publish(_from, [
        {climber: 90},
        {climber: 80},
        {climber: 65},
        {climber: 55},
      ]);
      final all = await stories(_activated);

      final story = of(
        all,
        climber,
        last,
      ).singleWhere((story) => story.family == MomentFamily.songHot100ClimbRun);
      expect(story.id, endsWith('#hot-100-run'));
      expect(story.publisher, MomentPublisher.sonusDaily);
      expect(story.variantId, startsWith('song-run-d'));
      final facts = story.facts.jump!;
      expect(facts.fromRank, 90);
      expect(facts.toRank, 55);
      expect(facts.weeks, 3);
      expect(facts.placesGained, 35, reason: 'positions, over three weeks');
      expect(facts.streamGain, 10, reason: 'streams, this week only');
      // CJ-040 or CJ-041, body text only.
      expect(
        story.body,
        anyOf(
          contains(
            'The song earned 245 qualified streams in the finalized chart '
            'week, 10 more than the preceding week.',
          ),
          contains('Qualified streams: 245 (up 10 on the week before).'),
        ),
      );
      expect(story.headline, isNot(contains(streamSentence)));
    });

    test('a jump inside a run is told as the run only (rule 5)', () async {
      final climber = _song('climber');
      final big = _song('big');
      final last = await publish(_from, [
        {climber: 95},
        {climber: 85},
        {climber: 75, big: 99},
        {climber: 40, big: 10},
      ]);
      final all = await stories(_activated);

      expect(jumps(of(all, climber, last)).map((story) => story.family), [
        MomentFamily.songHot100ClimbRun,
      ]);
      // Its first zones (Top 50, Top 40) have their own story.
      expect(jumps(of(all, climber, last)).single.facts.jump!.placesGained, 55);
    });

    test('a peak story tells the move; no jump headline repeats it '
        '(rule 7)', () async {
      final back = _song('back-to-peak');
      final big = _song('big');
      final last = await publish(_from, [
        {back: 6},
        {back: 60, big: 99},
        {back: 6, big: 30},
      ]);
      final all = await stories(_activated);

      expect(of(all, back, last).map((story) => story.family), [
        MomentFamily.songPeakMatch,
      ]);
    });

    test('jumps finishing in the Top 40 are never capped; other jumps follow '
        'the minor cap; runs are never capped (rule 10)', () async {
      final low = [for (var i = 0; i < 5; i++) _song('low-$i')];
      final high = [for (var i = 0; i < 5; i++) _song('high-$i')];
      final big = _song('big');
      // An earlier week inside the zones, so the jumps below enter no zone
      // for the first time (a first zone story would tell the move).
      final last = await publish(_from, [
        {
          for (final (i, song) in low.indexed) song: 55 - i,
          for (final (i, song) in high.indexed) song: 35 - i,
        },
        {
          big: 100,
          for (final (i, song) in low.indexed) song: 90 - i,
          for (final (i, song) in high.indexed) song: 80 - i,
        },
        {
          big: 2,
          for (final (i, song) in low.indexed) song: 60 - i,
          for (final (i, song) in high.indexed) song: 40 - i,
        },
      ]);
      final all = await stories(_activated);
      List<MomentStory> jumpsOf(List<ChartEntitySnapshot> songs) => [
        for (final song in songs) ...jumps(of(all, song, last)),
      ];

      expect(jumpsOf(high), hasLength(5));
      expect(
        jumpsOf(low),
        hasLength(lessThanOrEqualTo(3)),
        reason: 'capped like other minor stories',
      );
      expect(jumpsOf(low), isNotEmpty);
    });

    test('the streaming sentence needs a verified week, 10+ streams and a '
        'gain (rule 11)', () async {
      final fewer = _song('fewer');
      final quiet = _song('quiet');
      final big = _song('big');
      final last = await publish(
        _from,
        // An earlier week inside the zones, so the jumps enter no zone for
        // the first time.
        [
          {fewer: 45, quiet: 46},
          {fewer: 80, quiet: 81, big: 99},
          {fewer: 50, quiet: 51, big: 10},
        ],
        [
          {fewer: 100, quiet: 1},
          {fewer: 300, quiet: 2},
          {fewer: 200, quiet: 9},
        ],
      );
      final all = await stories(_activated);

      for (final song in [fewer, quiet]) {
        final story = jumps(of(all, song, last)).single;
        expect(story.family, MomentFamily.songHot100MajorJump);
        expect(story.body ?? '', isNot(contains(streamSentence)));
      }
    });

    test(
      'two climbing weeks, or a run broken by a fall, are not a run',
      () async {
        final two = _song('two');
        final broken = _song('broken');
        await publish(_from, [
          {two: 95, broken: 95},
          {two: 70, broken: 80},
          {two: 60, broken: 85},
          {broken: 60},
        ]);

        expect(
          (await stories(
            _activated,
          )).where((story) => story.family == MomentFamily.songHot100ClimbRun),
          isEmpty,
        );
      },
    );

    test('Bubbling Under moves are never Hot 100 jumps', () async {
      final arrival = _song('arrival-jump');
      final buClimb = _song('bu-climb');
      await publish(_from, [
        {arrival: 160, buClimb: 190},
        {arrival: 87, buClimb: 140},
      ]);

      expect(jumps(await stories(_activated)), isEmpty);
    });

    test('a missing week of history never counts', () async {
      final gap = _song('gap');
      final weeks = _Weeks(_from);
      for (final ranks in [
        {gap: 95},
        {gap: 85},
        {gap: 75},
        {gap: 60},
      ]) {
        final (start, events) = weeks.week(ranks);
        // The second week was never recorded as Moments.
        if (start == _from.add(const Duration(days: 7))) continue;
        await moments.publishFinalizedForWeek(
          chartType: ChartType.songs,
          weekStartUtc: start,
          events: events,
        );
      }

      expect(jumps(await stories(_activated)), isEmpty);
    });

    test(
      'composing again tells the same jump stories, word for word',
      () async {
        final jump = _song('jump');
        final big = _song('big');
        // An earlier week inside the zones, so the jump enters no zone for
        // the first time.
        await publish(_from, [
          {jump: 35},
          {jump: 80, big: 99},
          {jump: 40, big: 5},
        ]);

        String key(MomentStory story) =>
            '${story.id}|${story.headline}|${story.body}';
        final first = jumps(await stories(_activated));
        expect(first, hasLength(1));
        expect(
          [for (final story in jumps(await stories(_activated))) key(story)],
          [for (final story in first) key(story)],
        );
      },
    );

    test('weeks before activation tell no jumps and hold nothing', () async {
      final jump = _song('jump');
      await publish(DateTime.utc(2026, 8, 16), [
        {jump: 80},
        {jump: 40},
      ]);

      expect(jumps(await stories(_activated)), isEmpty);
      expect(await gated(_activated), isEmpty);
    });
  });
}
