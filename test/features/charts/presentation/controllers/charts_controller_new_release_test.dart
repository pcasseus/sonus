// App Update 1.3 new-release debuts through the real ChartsController:
// the controller reads release facts and every stored song debut since the
// write-once start, so a song's one new-release story is the same however
// much of the feed is paged in; with approval off nothing is read and no
// story changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/models/new_release_library_facts.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_release_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';

import '../../support/all_time_chart_fakes.dart';
import '../../support/moment_page_fakes.dart';

final _start = DateTime.utc(2026, 11, 15);
final _week1 = _start;
final _week2 = _start.add(const Duration(days: 7));

const _dead = ChartEntitySnapshot(
  entityId: 'song-dead',
  title: 'Dead',
  artistId: 'artist-1',
  artistName: 'Madison Beer',
);

void main() {
  // The career debut comes first (Tuesday of week 1); the weekly debut of
  // week 1 is published after the week closes. Three days of other news in
  // between keep the career debut off the first page.
  final careerDebut = _event(
    _dead,
    scope: ChartMomentScope.allTime,
    weekStart: _week1,
    at: _week1.add(const Duration(days: 2, hours: 10)),
    rank: 45,
  );
  final weeklyDebut = _event(
    _dead,
    scope: ChartMomentScope.finalized,
    weekStart: _week1,
    at: _week2.add(const Duration(hours: 9)),
    rank: 12,
  );
  final events = [
    careerDebut,
    weeklyDebut,
    for (var day = 1; day <= 3; day++)
      _event(
        ChartEntitySnapshot(
          entityId: 'song-other-$day',
          title: 'Other $day',
          artistId: 'artist-2',
          artistName: 'Someone Else',
        ),
        scope: ChartMomentScope.allTime,
        weekStart: _week1,
        at: _week1.add(Duration(days: 2 + day, hours: 12)),
        rank: 60 + day,
      ),
  ];

  bool isNewRelease(MomentStory story) =>
      story.variantId.startsWith('new-release-');

  MomentStory? storyOf(ChartsController controller, ChartMomentEvent event) {
    for (final story in controller.momentStories) {
      if (story.item.events.any((e) => e.id == event.id)) return story;
    }
    return null;
  }

  test('approved: the first debut (career) is the new single, on the first '
      'page and after reading every page', () async {
    final loaded = await _load(events, pageSize: 1, approved: true);
    final controller = loaded.controller;

    expect(controller.hasMoreMoments, isTrue);
    expect(storyOf(controller, careerDebut), isNull, reason: 'not loaded');
    final firstPage = storyOf(controller, weeklyDebut)!;
    expect(isNewRelease(firstPage), isFalse);

    while (controller.hasMoreMoments) {
      await controller.loadMoreMoments();
    }

    expect(
      storyOf(controller, careerDebut)!.headline,
      'Madison Beer debuts new single "Dead" on the Career Sonus Hot 100 at '
      '#45.',
    );
    expect(storyOf(controller, weeklyDebut)!.headline, firstPage.headline);
    expect(controller.momentStories.where(isNewRelease), hasLength(1));
    expect(loaded.historyReads, [_start]);
  });

  test('not approved (this build): nothing is read and the feed is '
      'unchanged', () async {
    final off = await _load(events, approved: false);
    final without = await _load(events, approved: false, loaders: false);

    expect(off.classificationReads, 0);
    expect(off.historyReads, isEmpty);
    expect(off.controller.momentStories.where(isNewRelease), isEmpty);
    expect(
      [for (final s in off.controller.momentStories) (s.id, s.headline)],
      [for (final s in without.controller.momentStories) (s.id, s.headline)],
    );
  });

  test('the default approval is off', () async {
    final defaults = await _load(events, approved: null);
    expect(defaults.historyReads, isEmpty);
    expect(defaults.controller.momentStories.where(isNewRelease), isEmpty);
  });

  test('approved but no recorded start: nothing is read or told', () async {
    final loaded = await _load(events, approved: true, start: false);
    expect(loaded.historyReads, isEmpty);
    expect(loaded.controller.momentStories.where(isNewRelease), isEmpty);
  });
}

ChartMomentEvent _event(
  ChartEntitySnapshot song, {
  required ChartMomentScope scope,
  required DateTime weekStart,
  required DateTime at,
  required int rank,
}) {
  final key = '${scope.name}-debut-${song.entityId}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-$key',
    chartType: ChartType.songs,
    scope: scope,
    eventType: ChartMomentEventType.debut,
    entity: song,
    weekStartUtc: weekStart,
    weekEndUtc: weekStart.add(const Duration(days: 7)),
    occurredAt: at,
    createdAt: at,
    currentRank: rank,
    currentPeakRank: rank,
    qualifiedStreamCount: 1,
  );
}

class _Loaded {
  _Loaded(this.controller);

  final ChartsController controller;
  int classificationReads = 0;
  final List<DateTime> historyReads = [];
}

Future<_Loaded> _load(
  List<ChartMomentEvent> events, {
  int pageSize = 200,
  required bool? approved,
  bool loaders = true,
  bool start = true,
}) async {
  late final _Loaded loaded;
  final moments = _Moments(events);
  final track = LibraryTrack(
    songId: _dead.entityId,
    title: 'Dead',
    artistId: 'artist-1',
    artistName: 'Madison Beer',
    albumId: 'album-1',
    albumTitle: 'Locket',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Locket',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: true,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 11, 8),
    isAvailable: true,
    filePath: 'C:/Music/dead.mp3',
  );
  final rules = ChartMomentRules(
    devicePolishFromUtc: DateTime.utc(2026, 10, 1),
    newReleaseDebutsFromUtc: start ? _start : null,
  );

  Future<NewReleaseClassifications> classifications() async {
    loaded.classificationReads++;
    return const NewReleaseClassifications();
  }

  Future<List<ChartMomentEvent>> history(DateTime fromUtc) async {
    loaded.historyReads.add(fromUtc);
    return [
      for (final event in events)
        if (!event.occurredAt.isBefore(fromUtc) &&
            event.eventType == ChartMomentEventType.debut)
          event,
    ];
  }

  final controller = approved == null
      ? ChartsController(
          allTimeCharts: _EmptyAllTimeCharts(),
          finalization: _NoFinalization(),
          charts: _NoHistory(),
          library: _library(track),
          moments: moments,
          now: () => DateTime.utc(2026, 11, 26, 12),
          momentPageSize: pageSize,
          momentRules: () async => rules,
          releaseEditions: _editions,
          singlePresentations: _singles,
          newReleaseClassifications: classifications,
          newReleaseDebutHistory: history,
        )
      : ChartsController(
          allTimeCharts: _EmptyAllTimeCharts(),
          finalization: _NoFinalization(),
          charts: _NoHistory(),
          library: _library(track),
          moments: moments,
          now: () => DateTime.utc(2026, 11, 26, 12),
          momentPageSize: pageSize,
          momentRules: () async => rules,
          releaseEditions: _editions,
          singlePresentations: _singles,
          newReleaseClassifications: loaders ? classifications : null,
          newReleaseDebutHistory: loaders ? history : null,
          newReleaseDebutsApproved: approved,
        );
  loaded = _Loaded(controller);
  addTearDown(controller.dispose);

  await controller.load();
  await pumpEventQueue();
  return loaded;
}

FakeChartLibrary _library(LibraryTrack track) => FakeChartLibrary(
  tracks: [track],
  albums: [
    LibraryAlbum(
      albumId: 'album-1',
      title: 'Locket',
      artistId: 'artist-1',
      artistName: 'Madison Beer',
      trackCount: 1,
      dateAdded: DateTime.utc(2026, 11, 8),
    ),
  ],
);

Future<List<LibraryReleaseEdition>> _editions() async => [
  LibraryReleaseEdition(
    edition: LibraryAlbumEdition(
      editionId: 'edition-1',
      albumId: 'album-1',
      title: 'Locket',
      type: AlbumEditionType.standard,
      isPrimary: true,
      dateAdded: DateTime.utc(2026, 11, 8),
      releaseDate: DateTime.utc(2026, 11, 7),
      releaseDatePrecision: ReleaseDatePrecision.day,
    ),
    trackCount: 1,
  ),
];

Future<Map<String, SongSinglePresentation>> _singles() async => {
  _dead.entityId: SongSinglePresentation(
    songId: _dead.entityId,
    releaseDate: ReleaseDate.of(2026, 11, 7),
    createdAt: DateTime.utc(2026, 11, 8),
    updatedAt: DateTime.utc(2026, 11, 8),
  ),
};

class _Moments implements ChartMomentRepository {
  _Moments(this.events);

  final List<ChartMomentEvent> events;

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async => momentPageOf(events, before: before, limit: limit);

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async =>
      momentPageOf(events, limit: limit ?? events.length);

  @override
  Future<ChartMomentEvent?> getById(String id) async => null;

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {}

  @override
  Future<bool> publishFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async => false;
}

class _EmptyAllTimeCharts implements AllTimeChartService {
  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async => AllTimeChart(
    chartType: chartType,
    comparisonStartUtc: DateTime.utc(2026, 11, 22),
    entries: const [],
  );
}

class _NoFinalization implements ChartFinalizationService {
  @override
  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async => const [];

  @override
  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) => throw UnimplementedError();

  @override
  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) =>
      throw UnimplementedError();
}

class _NoHistory implements ChartRepository {
  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async => const [];

  @override
  Future<ChartSnapshot?> getById(String id) async => null;

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async => null;

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {}
}
