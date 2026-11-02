// SN-50 Moments reachability (F3): made-up finalized weeks and plays go
// through the real weekly detectors, the real all-time Moment service, the
// real Moment store, the real feed aggregator and the real editorial desk.
// The tests pin which story families can actually publish, before and
// after the SN-50 rules start.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/models/chart_moment_feed_item.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/data/repositories/sqlite_chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_achievement_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_finalized_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_longevity_calculator.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_milestone_detector.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_family.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_story_planner.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// Made-up artists.
const _artists = {
  'mira': 'Mira Vale',
  'juno': 'Juno Park',
  'lanterns': 'The Lanterns',
  'ode': 'Ode Collective',
};

ChartEntitySnapshot _song(String id, String title, String artist) =>
    ChartEntitySnapshot(
      entityId: id,
      title: title,
      artistId: artist,
      artistName: _artists[artist]!,
      albumTitle: '$title (Album)',
    );

ChartEntitySnapshot _release(String id, String title, String artist) =>
    ChartEntitySnapshot(
      entityId: id,
      title: title,
      artistId: artist,
      artistName: _artists[artist]!,
    );

class _Lookups implements MomentLookups {
  _Lookups({this.covers = const {}});

  final Map<String, String> covers;

  @override
  String? artistName(String artistId) => _artists[artistId] ?? artistId;

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
  String? songCover(String songId) => covers[songId] ?? '/covers/$songId.jpg';

  @override
  String? releaseCover(String albumId) => '/covers/$albumId.jpg';

  @override
  String? currentSongCover(String songId) => songCover(songId);

  @override
  String? currentReleaseCover(String albumId) => releaseCover(albumId);

  @override
  String? artistPortrait(String artistId) => '/portraits/$artistId.jpg';
}

/// A finalized weekly chart, one week at a time, with the detectors the
/// finalization service runs.
class _WeeklyChart {
  _WeeklyChart(this.type, this._start);

  final ChartType type;
  DateTime _start;
  final List<ChartSnapshot> history = [];

  /// Finalizes the next week with these ranks and returns its events.
  List<ChartMomentEvent> week(Map<ChartEntitySnapshot, int> ranks) {
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
      id: 'chart_${type.name}_${start.millisecondsSinceEpoch}',
      chartType: type,
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
    final baseline =
        previous ??
        ChartSnapshot(
          id: 'baseline',
          chartType: type,
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
    return events;
  }
}

// Songs of the weekly scenario.
final _p = _song('paper-moon', 'Paper Moon', 'mira');
final _p2 = _song('second-light', 'Second Light', 'mira');
final _q = _song('quiet-hours', 'Quiet Hours', 'juno');
final _q3 = _song('third-wish', 'Third Wish', 'juno');
final _r = _song('river-song', 'River Song', 'lanterns');
final _t = _song('tin-roof', 'Tin Roof', 'ode');
final _s = _song('slow-burn', 'Slow Burn', 'ode');

// Releases of the weekly scenario.
final _a1 = _release('night-market', 'Night Market', 'mira');
final _a2 = _release('day-market', 'Day Market', 'mira');
final _b1 = _release('glass-house', 'Glass House', 'juno');
final _b2 = _release('stone-house', 'Stone House', 'juno');
final _c1 = _release('field-notes', 'Field Notes', 'lanterns');
final _d1 = _release('low-hum', 'Low Hum', 'ode');

/// Nine weeks of songs: a #190 debut that climbs to #1 through every zone,
/// a #1 debut that holds, a re-entry, a peak match, a new peak, a
/// self-replacement and an artist's repeat #1.
List<Map<ChartEntitySnapshot, int>> get _songWeeks => [
  {_q: 1, _t: 9, _r: 30, _s: 40, _p: 190},
  {_q: 1, _t: 7, _r: 8, _p: 150},
  {_q: 1, _r: 3, _t: 12, _s: 45, _p: 60},
  {_q: 1, _p: 4, _r: 6, _t: 13, _s: 46},
  {_p: 1, _q: 2, _r: 3, _t: 14, _p2: 20, _s: 47},
  {_p2: 1, _p: 2, _q: 3, _r: 4, _t: 15},
  {_r: 1, _p2: 2, _p: 3, _q: 4, _q3: 30},
  {_q3: 1, _r: 2, _p2: 3, _p: 4},
  {_p: 1, _q3: 2, _r: 3},
];

/// Six weeks of releases.
List<Map<ChartEntitySnapshot, int>> get _releaseWeeks => [
  {_b1: 1, _a1: 12, _d1: 30, _c1: 150},
  {_b1: 1, _a1: 4, _c1: 60},
  {_a1: 1, _b1: 2, _a2: 5, _c1: 7, _d1: 35},
  {_a2: 1, _a1: 2, _c1: 6, _b1: 8},
  {_b2: 1, _a2: 2, _a1: 3, _c1: 9},
  {_a1: 1, _b2: 2, _a2: 3},
];

class _Plays implements QualifiedPlayRepository {
  final List<QualifiedPlay> all = [];

  void add(LibraryTrack track, DateTime at, {int times = 1}) {
    for (var i = 0; i < times; i++) {
      final when = at.add(Duration(seconds: i));
      final id = 'play-${all.length + 1}';
      all.add(
        QualifiedPlay(
          id: id,
          playbackSessionId: 'session-$id',
          songId: track.songId,
          artistId: track.artistId,
          albumId: track.albumId,
          albumEditionId: track.albumEditionId,
          qualifiedAt: when.toUtc(),
          listenedDuration: const Duration(seconds: 120),
          trackDuration: const Duration(seconds: 200),
          createdAt: when.toUtc(),
        ),
      );
    }
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => List.of(all);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Library implements LibraryQueryRepository {
  final List<LibraryTrack> tracks = [];
  final List<LibraryAlbum> albums = [];

  LibraryTrack add(String id, String title, String artist) {
    final name = _artists[artist] ?? artist;
    final track = LibraryTrack(
      songId: id,
      title: title,
      artistId: artist,
      artistName: name,
      albumId: 'album-$id',
      albumTitle: '$title (Album)',
      albumEditionId: 'edition-$id',
      albumEditionTitle: '$title (Album)',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 9, 1),
      isAvailable: true,
      isSongBlocked: false,
    );
    tracks.add(track);
    albums.add(
      LibraryAlbum(
        albumId: 'album-$id',
        title: '$title (Album)',
        artistId: artist,
        artistName: name,
        trackCount: 1,
        dateAdded: DateTime.utc(2026, 9, 1),
      ),
    );
    return track;
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<List<LibraryArtist>> getArtists() async => [
    for (final artist in {for (final track in tracks) track.artistId})
      LibraryArtist(
        artistId: artist,
        name: _artists[artist] ?? artist,
        albumCount: 1,
        songCount: 1,
        dateAdded: DateTime.utc(2026, 9, 1),
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Where a scenario runs: before the SN-50 rules, or after.
class _Era {
  const _Era(this.weeksFromUtc, this.playsOn);

  /// The first finalized week of the weekly scenarios.
  final DateTime weeksFromUtc;

  /// A Tuesday (local) for the all-time plays.
  final DateTime playsOn;
}

final _legacy = _Era(DateTime.utc(2026, 8, 16), DateTime(2026, 10, 27));

/// The nine SN-50 draft families (N-2 to N-6), held by the approved-family
/// guard until their lines are approved.
const _nineDrafts = {
  MomentFamily.songSelfReplacement,
  MomentFamily.songFirstThreshold,
  MomentFamily.songThresholds,
  MomentFamily.artistRepeatNumberOne,
  MomentFamily.releaseSelfReplacement,
  MomentFamily.releaseFirstThreshold,
  MomentFamily.releaseThresholds,
  MomentFamily.artistRepeatNumberOneRelease,
  MomentFamily.artistSimultaneousReleases,
};

/// Those still held; each editorial batch that approves a family removes
/// it here (Batch 6: the first-zone families).
const _stillDraft = <MomentFamily>{};

final _refined = _Era(DateTime.utc(2026, 11, 1), DateTime(2026, 11, 17));

/// An approved build first ran as the refined era began (SN-50 R2).
final _activated = ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 11, 1));

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

  Future<void> publishWeeks(
    ChartType type,
    DateTime from,
    List<Map<ChartEntitySnapshot, int>> weeks,
  ) async {
    final chart = _WeeklyChart(type, from);
    for (final ranks in weeks) {
      final events = chart.week(ranks);
      await moments.publishFinalizedForWeek(
        chartType: type,
        weekStartUtc: chart.history.last.weekStartUtc,
        events: events,
      );
    }
  }

  /// A deep chart (5 songs with 30 plays, 115 with 10), then plays of one
  /// song that debuts at #121 and jumps to #6 with one play.
  Future<void> recordDeepClimb(_Era era, ChartMomentRules rules) async {
    final library = _Library();
    final plays = _Plays();
    final early = era.playsOn.subtract(const Duration(days: 30));
    for (var i = 0; i < 120; i++) {
      final track = library.add('deep-$i', 'Deep Cut $i', 'deep-artist-$i');
      plays.add(track, early.add(Duration(minutes: i)), times: i < 5 ? 30 : 10);
    }
    final climber = library.add('lantern-light', 'Lantern Light', 'mira');
    plays.add(climber, era.playsOn, times: 11);
    await _service(plays, library, moments).record(
      referenceLocal: era.playsOn.add(const Duration(days: 1)),
      rules: rules,
    );
  }

  /// Three songs racing to #1, two by one artist.
  Future<void> recordRace(_Era era, [ChartMomentRules? rules]) async {
    final library = _Library();
    final plays = _Plays();
    final first = library.add('first-steps', 'First Steps', 'juno');
    final second = library.add('second-wind', 'Second Wind', 'juno');
    final rival = library.add('wild-card', 'Wild Card', 'lanterns');
    var at = era.playsOn;
    void play(LibraryTrack track) {
      at = at.add(const Duration(minutes: 1));
      plays.add(track, at);
    }

    play(first);
    play(second);
    play(second);
    for (var i = 0; i < 4; i++) {
      play(rival);
    }
    await _service(plays, library, moments).record(
      referenceLocal: era.playsOn.add(const Duration(days: 1)),
      rules: rules ?? _activated,
    );
  }

  Future<List<MomentStory>> stories({
    Map<String, String> covers = const {},
    ChartMomentRules? rules,
  }) => moments.getRecent().then(
    (events) => MomentEditorialDesk(
      lookups: _Lookups(covers: covers),
      rules: rules ?? _activated,
    ).compose(const ChartMomentFeedAggregator().aggregate(events)),
  );

  /// Refined stories held by the approved-family guard: planned, never
  /// published (SN-50 release safety).
  Future<List<GatedMoment>> held({ChartMomentRules? rules}) =>
      moments.getRecent().then(
        (events) => [
          for (final gated in MomentEditorialDesk(
            lookups: _Lookups(),
            rules: rules ?? _activated,
          ).copyGated(const ChartMomentFeedAggregator().aggregate(events)))
            if (gated.kind == GatedMomentKind.unapprovedCopy) gated,
        ],
      );

  MomentFacts heldFacts(GatedMoment gated) =>
      MomentFacts.of(gated.story!, _Lookups(), refined: true);

  /// One subject's planned stories, told or held, are exactly [expected];
  /// only the families still in [_stillDraft] are held.
  void expectPlanned(
    List<MomentStory> told,
    List<GatedMoment> heldStories,
    List<MomentFamily> expected,
  ) {
    expect([
      for (final story in told) story.family,
      for (final gated in heldStories) gated.family!,
    ], unorderedEquals(expected));
    expect(
      {for (final gated in heldStories) gated.family},
      {
        for (final family in expected)
          if (_stillDraft.contains(family)) family,
      },
    );
  }

  /// The one planned story matching [matches], told or held: its family,
  /// facts and id. A family still in [_stillDraft] is held, never told.
  Future<(MomentFamily, MomentFacts, String)> plannedOne(
    bool Function(ChartMomentFeedItem story, MomentFamily family) matches,
  ) async {
    final told = [
      for (final story in await stories())
        if (matches(story.item, story.family)) story,
    ];
    final heldOnes = [
      for (final gated in await held())
        if (matches(gated.story!, gated.family!)) gated,
    ];
    expect(told.length + heldOnes.length, 1);
    if (told.isNotEmpty) {
      final story = told.single;
      expect(_stillDraft, isNot(contains(story.family)));
      return (story.family, story.facts, story.id);
    }
    final gated = heldOnes.single;
    expect(_stillDraft, contains(gated.family));
    return (gated.family!, heldFacts(gated), gated.id);
  }

  /// The facts of each planned story, told or held.
  Map<MomentFamily, MomentFacts> plannedFacts(
    List<MomentStory> told,
    List<GatedMoment> heldStories,
  ) => {
    for (final story in told) story.family: story.facts,
    for (final gated in heldStories) gated.family!: heldFacts(gated),
  };

  Future<Set<MomentFamily>> reachable(
    _Era era, {
    ChartMomentRules? rules,
  }) async {
    await publishWeeks(ChartType.songs, era.weeksFromUtc, _songWeeks);
    await publishWeeks(ChartType.albums, era.weeksFromUtc, _releaseWeeks);
    await recordDeepClimb(era, rules ?? _activated);
    await recordRace(era, rules);
    return {for (final story in await stories(rules: rules)) story.family};
  }

  test('before the SN-50 rules: 17 families publish, as first '
      'published', () async {
    final families = await reachable(_legacy);

    expect(families, {
      MomentFamily.songBubblingUnderDebut,
      MomentFamily.songFirstNumberOne,
      MomentFamily.songReturnsToNumberOne,
      MomentFamily.songNewPeak,
      MomentFamily.artistFirstTop10,
      MomentFamily.artistNthTop10,
      MomentFamily.artistFirstNumberOne,
      MomentFamily.artistNthNumberOne,
      MomentFamily.artistTopArtist,
      MomentFamily.artistSimultaneous,
      MomentFamily.releaseDebutNumberOne,
      MomentFamily.releaseDebut,
      MomentFamily.releaseReachesNumberOne,
      MomentFamily.releaseReturnsToNumberOne,
      MomentFamily.releaseNewPeak,
      MomentFamily.artistFirstNumberOneRelease,
      MomentFamily.artistNthNumberOneRelease,
    });
    // Plays before the rules never record the new zone entries.
    final allTimeZones = (await moments.getRecent()).where(
      (event) =>
          event.scope == ChartMomentScope.allTime &&
          event.eventType == ChartMomentEventType.firstThresholdEntry,
    );
    expect(allTimeZones.map((event) => event.threshold).toSet(), {100});
  });

  test('with the SN-50 rules: the approved families publish, including peak '
      'matches and longevity; draft families are held; '
      'releaseWeeksMilestone stays unwired', () async {
    final families = await reachable(_refined);

    expect(families, {
      MomentFamily.songDebutNumberOne,
      MomentFamily.songDebutTop10,
      MomentFamily.songDebut,
      MomentFamily.songBubblingUnderDebut,
      MomentFamily.songHot100Breakthrough,
      MomentFamily.songReturnsToNumberOne,
      MomentFamily.songNewPeak,
      MomentFamily.songPeakMatch,
      MomentFamily.songBiggestGainer,
      MomentFamily.songReentry,
      MomentFamily.songWeeksMilestone,
      MomentFamily.artistFirstTop10,
      MomentFamily.artistNthTop10,
      MomentFamily.artistFirstNumberOne,
      MomentFamily.artistTopArtist,
      MomentFamily.artistSimultaneous,
      MomentFamily.releaseDebutNumberOne,
      MomentFamily.releaseDebut,
      MomentFamily.releaseReturnsToNumberOne,
      MomentFamily.releaseNewPeak,
      MomentFamily.releaseReentry,
      MomentFamily.artistFirstNumberOneRelease,
      ..._nineDrafts.difference(_stillDraft),
    });
    // Planned under the rules, but their headlines are not approved yet.
    expect({for (final gated in await held()) gated.family}, _stillDraft);
    expect(
      families.intersection({for (final gated in await held()) gated.family}),
      isEmpty,
      reason: 'a held family never publishes',
    );
  });

  test('scenario 7: a #190 debut, then each first zone once, with its '
      'scope', () async {
    await publishWeeks(ChartType.songs, _refined.weeksFromUtc, _songWeeks);
    final lastWeek = _refined.weeksFromUtc.add(const Duration(days: 28));
    final paper = [
      for (final story in (await stories()).reversed)
        if (story.item.entity.entityId == _p.entityId &&
            !story.item.weekStartUtc.isAfter(lastWeek))
          story,
    ];

    final zones = <int>[];
    for (final story in paper) {
      switch (story.family) {
        case MomentFamily.songBubblingUnderDebut:
          zones.add(200);
          expect(story.headline, contains('#190'));
          expect(story.headline, contains('Sonus Bubbling Under'));
        case MomentFamily.songHot100Breakthrough:
          zones.add(100);
        case MomentFamily.songFirstThreshold:
          expect(_stillDraft, isNot(contains(story.family)));
          zones.add(story.facts.threshold!);
        case MomentFamily.songThresholds:
          expect(_stillDraft, isNot(contains(story.family)));
          zones.addAll(story.facts.thresholds);
        case MomentFamily.artistFirstNumberOne:
          zones.add(1);
        default:
          break;
      }
      expect(story.facts.weekly, isTrue);
      expect(story.headline, isNot(contains('this stream')));
      expect(story.body ?? '', isNot(contains('this stream')));
    }
    // First zones are planned once each, and held until approved.
    for (final gated in await held()) {
      final story = gated.story!;
      if (story.entity.entityId != _p.entityId ||
          story.weekStartUtc.isAfter(lastWeek)) {
        continue;
      }
      final facts = heldFacts(gated);
      expect(facts.weekly, isTrue);
      switch (gated.family) {
        case MomentFamily.songFirstThreshold:
          zones.add(facts.threshold!);
        case MomentFamily.songThresholds:
          zones.addAll(facts.thresholds);
        default:
          break;
      }
    }
    expect(zones.toSet(), {
      200,
      100,
      75,
      50,
      40,
      30,
      25,
      20,
      15,
      10,
      5,
      3,
      2,
      1,
    });
    expect(zones, hasLength(14), reason: 'each zone is told once');
  });

  test('scenario 8: five deep debuts on one day are five stories; minor '
      'stories before the rules stay capped at three', () async {
    Future<int> deepDebuts(_Era era, String tag) async {
      final library = _Library();
      final plays = _Plays();
      final early = era.playsOn.subtract(const Duration(days: 30));
      for (var i = 0; i < 120; i++) {
        final track = library.add('$tag-floor-$i', 'Floor $i', 'floor-$i');
        plays.add(track, early.add(Duration(minutes: i)), times: 10);
      }
      for (var i = 0; i < 5; i++) {
        final track = library.add('$tag-new-$i', 'New $i', 'ode');
        plays.add(track, era.playsOn.add(Duration(minutes: i)));
      }
      await _service(plays, library, moments).record(
        referenceLocal: era.playsOn.add(const Duration(days: 1)),
        rules: _activated,
      );
      return (await stories())
          .where(
            (story) =>
                story.family == MomentFamily.songBubblingUnderDebut &&
                story.item.entity.entityId.startsWith('$tag-new-'),
          )
          .length;
    }

    expect(await deepDebuts(_refined, 'after'), 5);
    expect(await deepDebuts(_legacy, 'before'), 3);

    final releases = _WeeklyChart(ChartType.albums, _refined.weeksFromUtc);
    final week = releases.week({
      for (var i = 0; i < 5; i++)
        _release('deep-release-$i', 'Deep Release $i', 'ode'): 120 + i,
    });
    await moments.publishFinalizedForWeek(
      chartType: ChartType.albums,
      weekStartUtc: _refined.weeksFromUtc,
      events: week,
    );
    final weekly = (await stories()).where(
      (story) =>
          story.family == MomentFamily.releaseDebut && story.facts.weekly,
    );
    expect(weekly, hasLength(5));
  });

  test('scenario 8: a career milestone on the same play never replaces the '
      'entry story', () async {
    await recordRace(_refined);
    final second = [
      for (final story in await stories())
        if (story.item.entity.entityId == 'second-wind' &&
            story.item.chartType == ChartType.songs)
          story.family,
    ];

    expect(
      second,
      containsAll([MomentFamily.songDebutTop10, MomentFamily.artistNthTop10]),
    );
  });

  test('scenario 9: a weekly #1 names only the displaced leader; an artist '
      'replacing their own #1 is not a dethroning', () async {
    await publishWeeks(ChartType.songs, _refined.weeksFromUtc, _songWeeks);
    final all = await stories(
      covers: {
        _p.entityId: '/covers/mira.jpg',
        _p2.entityId: '/covers/mira.jpg',
      },
    );
    MomentStory numberOne(ChartEntitySnapshot song, int week) =>
        all.singleWhere(
          (story) =>
              story.item.entity.entityId == song.entityId &&
              story.family.isNumberOne &&
              story.item.weekStartUtc ==
                  _refined.weeksFromUtc.add(Duration(days: 7 * week)),
        );

    final dethroning = numberOne(_p, 4);
    expect(dethroning.facts.rivalTitle, _q.title);
    expect(dethroning.facts.rivalArtist, 'Juno Park');

    // The artist's own replacement is no dethroning: it is planned as a
    // self-replacement (told since Batch 7).
    final fifth = _refined.weeksFromUtc.add(const Duration(days: 35));
    final (family, facts, _) = await plannedOne(
      (story, family) =>
          story.entity.entityId == _p2.entityId &&
          story.weekStartUtc == fifth &&
          family.isNumberOne,
    );
    expect(family, MomentFamily.songSelfReplacement);
    expect(facts.rivalTitle, _p.title);
  });

  test('a weekly repeat #1 counts the stored weeks and names the weekly '
      'chart', () async {
    await publishWeeks(ChartType.songs, _refined.weeksFromUtc, _songWeeks);
    // Told since Batch 8, under its planned story id.
    final (family, facts, id) = await plannedOne(
      (story, family) =>
          family == MomentFamily.artistRepeatNumberOne &&
          story.entity.entityId == _q3.entityId,
    );
    expect(family, MomentFamily.artistRepeatNumberOne);
    expect(facts.ordinal, 2);
    expect(facts.weekly, isTrue);
    expect(id, endsWith('#number-one'));
  });

  group('SN-50 R2 activation', () {
    test('without an activation the refined-era scenarios keep the earlier '
        'families and record no zone entries', () async {
      final families = await reachable(
        _refined,
        rules: ChartMomentRules.legacy,
      );

      expect(
        families,
        isNot(
          anyOf(
            contains(MomentFamily.songFirstThreshold),
            contains(MomentFamily.songThresholds),
            contains(MomentFamily.songSelfReplacement),
            contains(MomentFamily.artistRepeatNumberOne),
          ),
        ),
      );
      final told = await stories(rules: ChartMomentRules.legacy);
      expect(told.where((story) => story.facts.refined), isEmpty);
      final allTimeZones = (await moments.getRecent()).where(
        (event) =>
            event.scope == ChartMomentScope.allTime &&
            event.eventType == ChartMomentEventType.firstThresholdEntry,
      );
      expect(allTimeZones.map((event) => event.threshold).toSet(), {100});
    });

    test('the chart week running at activation keeps the earlier rules; '
        'later weeks use the new ones', () async {
      final activatedAt = _refined.weeksFromUtc.add(const Duration(days: 3));
      final rules = ChartMomentRules(activatedAtUtc: activatedAt);
      await publishWeeks(ChartType.songs, _refined.weeksFromUtc, _songWeeks);

      final weekly = (await stories(
        rules: rules,
      )).where((story) => story.facts.weekly).toList();

      final running = weekly.where(
        (story) => story.item.weekStartUtc == _refined.weeksFromUtc,
      );
      expect(running, isNotEmpty);
      expect(running.where((story) => story.facts.refined), isEmpty);
      final later = weekly.where(
        (story) => story.item.weekStartUtc.isAfter(activatedAt),
      );
      expect(later, isNotEmpty);
      expect(later.every((story) => story.facts.refined), isTrue);
    });

    test('real-time stories and zone entries use the new rules only from '
        'the activation instant', () async {
      final activatedAt = _refined.playsOn
          .add(const Duration(minutes: 4, seconds: 30))
          .toUtc();
      final rules = ChartMomentRules(activatedAtUtc: activatedAt);
      await recordDeepClimb(_refined, rules);
      await recordRace(_refined, rules);

      final told = await stories(rules: rules);
      expect(told.where((story) => story.facts.refined), isNotEmpty);
      expect(told.where((story) => !story.facts.refined), isNotEmpty);
      for (final story in told) {
        expect(
          story.facts.refined,
          !story.occurredAt.isBefore(activatedAt),
          reason: story.id,
        );
      }
      final zones = (await moments.getRecent()).where(
        (event) =>
            event.scope == ChartMomentScope.allTime &&
            event.eventType == ChartMomentEventType.firstThresholdEntry &&
            event.threshold != 100,
      );
      expect(
        zones.where((event) => event.occurredAt.isBefore(activatedAt)),
        isEmpty,
      );
    });
  });

  group('SN-50 R3 entries and first thresholds', () {
    /// 149 songs with two plays a month ago; the climber reached two plays
    /// last, at #150 (Bubbling Under), and its next play takes it straight
    /// to #1.
    Future<void> recordJumpToNumberOne(ChartMomentRules rules) async {
      final library = _Library();
      final plays = _Plays();
      final early = _refined.playsOn.subtract(const Duration(days: 30));
      for (var i = 0; i < 149; i++) {
        final track = library.add('field-$i', 'Field $i', 'field-artist-$i');
        plays.add(track, early.add(Duration(minutes: i)), times: 2);
      }
      final climber = library.add('lucky-star', 'Lucky Star', 'mira');
      plays.add(climber, early.add(const Duration(hours: 5)), times: 2);
      plays.add(climber, _refined.playsOn);
      await _service(plays, library, moments).record(
        referenceLocal: _refined.playsOn.add(const Duration(days: 1)),
        rules: rules,
      );
    }

    List<MomentStory> storiesOf(
      List<MomentStory> all,
      String entityId,
      ChartType type, {
      DateTime? weekStartUtc,
    }) => [
      for (final story in all.reversed)
        if (story.item.entity.entityId == entityId &&
            story.item.chartType == type &&
            story.item.subjectType != ChartMomentFeedSubjectType.artist &&
            (weekStartUtc == null || story.item.weekStartUtc == weekStartUtc))
          story,
    ];

    test('an all-time jump from Bubbling Under straight to #1 keeps its '
        'Top 100 entry; only #1 and the Top 10 stand alone', () async {
      await recordJumpToNumberOne(_activated);
      final all = await stories();

      final songs = storiesOf(all, 'lucky-star', ChartType.songs);
      final gated = await held();
      List<GatedMoment> heldOf(String entityId) => [
        for (final moment in gated)
          if (moment.story!.entity.entityId == entityId &&
              moment.story!.subjectType != ChartMomentFeedSubjectType.artist)
            moment,
      ];
      final heldSongs = heldOf('lucky-star');
      expectPlanned(songs, heldSongs, [
        MomentFamily.artistFirstNumberOne,
        MomentFamily.songHot100Breakthrough,
        MomentFamily.songFirstThreshold,
        MomentFamily.songThresholds,
      ]);
      final songFacts = plannedFacts(songs, heldSongs);
      expect(songFacts[MomentFamily.artistFirstNumberOne]!.rank, 1);
      expect(songFacts[MomentFamily.songFirstThreshold]!.threshold, 10);
      expect(songFacts[MomentFamily.songThresholds]!.thresholds, [
        75,
        50,
        40,
        30,
        25,
        20,
        15,
        5,
        3,
        2,
      ]);

      final releases = storiesOf(all, 'album-lucky-star', ChartType.albums);
      final heldReleases = heldOf('album-lucky-star');
      expectPlanned(releases, heldReleases, [
        MomentFamily.artistFirstNumberOneRelease,
        MomentFamily.releaseFirstThreshold,
        MomentFamily.releaseThresholds,
      ]);
      final releaseFacts = plannedFacts(releases, heldReleases);
      expect(releaseFacts[MomentFamily.releaseThresholds]!.thresholds, [
        100,
        75,
        50,
        40,
        30,
        25,
        20,
        15,
        5,
        3,
        2,
      ]);
    });

    test('without an activation the jump records no Top 100 entry', () async {
      await recordJumpToNumberOne(ChartMomentRules.legacy);

      final entries = (await moments.getRecent()).where(
        (event) =>
            event.entity.entityId == 'lucky-star' &&
            event.eventType == ChartMomentEventType.firstThresholdEntry,
      );
      expect(entries, isEmpty);
    });

    test('recording the same plays again mints no new story', () async {
      await recordJumpToNumberOne(_activated);
      final first = await stories();
      final events = await moments.getRecent();

      await recordJumpToNumberOne(_activated);
      final again = await stories();

      expect(
        (await moments.getRecent()).map((event) => event.id).toSet(),
        events.map((event) => event.id).toSet(),
      );
      expect(again.map((story) => story.id), first.map((story) => story.id));
      expect(
        again.map((story) => story.headline),
        first.map((story) => story.headline),
      );
      expect(
        again.map((story) => story.id).toSet(),
        hasLength(again.length),
        reason: 'story ids are unique',
      );
    });

    test('weekly: a #1 debut, and jumps #40 to #1, #80 to #8 and #120 to '
        '#60, each with one entry and only #1 and the Top 10 alone', () async {
      final top = _song('high-noon', 'High Noon', 'juno');
      final forty = _song('long-road', 'Long Road', 'mira');
      final eighty = _song('red-kite', 'Red Kite', 'lanterns');
      final deep = _song('low-tide', 'Low Tide', 'ode');
      final chart = _WeeklyChart(ChartType.songs, _refined.weeksFromUtc);
      final weeks = [
        {top: 1, forty: 40, eighty: 80, deep: 120},
        {forty: 1, top: 2, eighty: 8, deep: 60},
      ];
      for (final ranks in weeks) {
        await moments.publishFinalizedForWeek(
          chartType: ChartType.songs,
          weekStartUtc: chart._start,
          events: chart.week(ranks),
        );
      }
      final all = await stories();
      final second = _refined.weeksFromUtc.add(const Duration(days: 7));
      List<MomentFamily> families(ChartEntitySnapshot song, DateTime week) => [
        for (final story in storiesOf(
          all,
          song.entityId,
          ChartType.songs,
          weekStartUtc: week,
        ))
          story.family,
      ];

      expect(families(top, _refined.weeksFromUtc), [
        MomentFamily.songDebutNumberOne,
        MomentFamily.artistFirstNumberOne,
      ]);
      final gated = await held();
      List<GatedMoment> heldOf(ChartEntitySnapshot song) => [
        for (final moment in gated)
          if (moment.story!.entity.entityId == song.entityId &&
              moment.story!.weekStartUtc == second)
            moment,
      ];

      List<MomentStory> toldOf(ChartEntitySnapshot song) =>
          storiesOf(all, song.entityId, ChartType.songs, weekStartUtc: second);

      // #40 to #1: the #1 story tells the move (approved rule 6), so no
      // jump headline; its zones are told once approved.
      expectPlanned(toldOf(forty), heldOf(forty), [
        MomentFamily.artistFirstNumberOne,
        MomentFamily.songFirstThreshold,
        MomentFamily.songThresholds,
      ]);
      expect(
        plannedFacts(
          toldOf(forty),
          heldOf(forty),
        )[MomentFamily.songThresholds]!.thresholds,
        [30, 25, 20, 15, 5, 3, 2],
      );
      // #80 to #8: the week's biggest gainer keeps its story (rule 4).
      expectPlanned(toldOf(eighty), heldOf(eighty), [
        MomentFamily.songBiggestGainer,
        MomentFamily.songFirstThreshold,
        MomentFamily.songThresholds,
      ]);
      expect(
        plannedFacts(
          toldOf(eighty),
          heldOf(eighty),
        )[MomentFamily.songThresholds]!.thresholds,
        [75, 50, 40, 30, 25, 20, 15],
      );
      // #120 to #60: a Hot 100 breakthrough from Bubbling Under, never a
      // Hot 100 jump.
      expectPlanned(toldOf(deep), heldOf(deep), [
        MomentFamily.songHot100Breakthrough,
        MomentFamily.songFirstThreshold,
      ]);

      // A second finalization of a week publishes nothing.
      final replay = _WeeklyChart(ChartType.songs, _refined.weeksFromUtc);
      for (final ranks in weeks) {
        final week = replay._start;
        expect(
          await moments.publishFinalizedForWeek(
            chartType: ChartType.songs,
            weekStartUtc: week,
            events: replay.week(ranks),
          ),
          isFalse,
        );
      }
      expect(
        (await stories()).map((story) => story.id),
        all.map((story) => story.id),
      );
    });
  });

  group('SN-50 reconciliation', () {
    /// A self-replacement is planned (never told as a dethroning), but its
    /// headlines are not approved, so it is held and nothing publishes.
    Future<void> expectHeldSelfReplacement(
      bool Function(ChartMomentFeedItem story) matches, {
      required MomentFamily family,
      required String replaced,
      required bool weekly,
    }) async {
      final (planned, facts, _) = await plannedOne(
        (story, planned) => matches(story) && planned.isNumberOne,
      );
      expect(planned, family);
      expect(facts.weekly, weekly);
      // Only the artist's own previous #1 is named, never a rival.
      expect(facts.rivalTitle, replaced);
    }

    test('SN-50 reconciliation: an all-time song replacing its own '
        'artist\'s #1 is a self-replacement that names no rival', () async {
      await recordRace(_refined);

      await expectHeldSelfReplacement(
        (story) =>
            story.entity.entityId == 'second-wind' &&
            story.chartType == ChartType.songs,
        family: MomentFamily.songSelfReplacement,
        replaced: 'First Steps',
        weekly: false,
      );
    });

    test('SN-50 reconciliation: an all-time release replacing its own '
        'artist\'s #1 release is a self-replacement that names no '
        'rival', () async {
      await recordRace(_refined);

      await expectHeldSelfReplacement(
        (story) =>
            story.entity.entityId == 'album-second-wind' &&
            story.chartType == ChartType.albums,
        family: MomentFamily.releaseSelfReplacement,
        replaced: 'First Steps (Album)',
        weekly: false,
      );
    });

    test('SN-50 reconciliation: a weekly release replacing its own '
        'artist\'s #1 release is a self-replacement that names no '
        'rival', () async {
      await publishWeeks(
        ChartType.albums,
        _refined.weeksFromUtc,
        _releaseWeeks,
      );
      final fourth = _refined.weeksFromUtc.add(const Duration(days: 21));

      await expectHeldSelfReplacement(
        (story) =>
            story.entity.entityId == _a2.entityId &&
            story.weekStartUtc == fourth,
        family: MomentFamily.releaseSelfReplacement,
        replaced: _a1.title,
        weekly: true,
      );
    });

    test('SN-50 reconciliation: a weekly release re-entry at #101-200 is a '
        'guaranteed releaseReentry story, never dropped by the minor '
        'cap', () async {
      final back = _release('harbour-lights', 'Harbour Lights', 'lanterns');
      final chart = _WeeklyChart(ChartType.albums, _refined.weeksFromUtc);
      final weeks = [
        {_b1: 1, back: 60},
        {_b1: 1},
        {
          _b1: 1,
          back: 160,
          // Many minor deep debuts the same week.
          for (var i = 0; i < 6; i++)
            _release('deep-$i', 'Deep Release $i', 'ode'): 120 + i,
        },
      ];
      for (final ranks in weeks) {
        await moments.publishFinalizedForWeek(
          chartType: ChartType.albums,
          weekStartUtc: chart._start,
          events: chart.week(ranks),
        );
      }
      final third = _refined.weeksFromUtc.add(const Duration(days: 14));

      final reentry = (await stories()).where(
        (story) =>
            story.item.entity.entityId == back.entityId &&
            story.item.weekStartUtc == third,
      );
      expect(reentry.map((story) => story.family), [
        MomentFamily.releaseReentry,
      ]);
      expect(reentry.single.facts.rank, 160);
      expect(reentry.single.facts.refined, isTrue);
    });
  });
}

AllTimeMomentService _service(
  _Plays plays,
  _Library library,
  SqliteChartMomentRepository moments,
) => AllTimeMomentService(
  qualifiedPlays: plays,
  library: library,
  moments: moments,
  activationUtc: DateTime.utc(2026, 10, 25),
);
