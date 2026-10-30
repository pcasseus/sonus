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

  Future<DateTime> publish(DateTime from) async {
    final weeks = _Weeks(from);
    late DateTime last;
    for (final ranks in _songWeeks) {
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
}
