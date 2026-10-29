// SN-50 F-Q25/F-Q26/A-Q29: the Moments feed is read a page at a time in
// whole days, filtered, marked when new, and opens surviving editions.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/moments_last_seen_store.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_category.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/models/charts_presentation_mode.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

import '../../support/all_time_chart_fakes.dart';
import '../../support/moment_page_fakes.dart';

void main() {
  group('paging', () {
    test('a first page tells whole days exactly as the full feed does, and '
        'reading on reaches the same feed', () async {
      final events = _mixedHistory();
      final full = await _controller(events: events, pageSize: 10000);
      final paged = await _controller(events: events, pageSize: 2);

      expect(paged.controller.hasMoreMoments, isTrue);
      expect(
        paged.moments.pageReads,
        lessThan(events.length ~/ 2),
        reason: 'a load reads a bounded number of pages',
      );

      final firstPage = _summary(paged.controller.momentStories);
      expect(firstPage, isNotEmpty);
      expect(
        firstPage,
        _summary(full.controller.momentStories).take(firstPage.length),
        reason: 'the loaded days tell the stories a full read tells',
      );

      while (paged.controller.hasMoreMoments) {
        await paged.controller.loadMoreMoments();
      }

      expect(
        _summary(paged.controller.momentStories),
        _summary(full.controller.momentStories),
      );
    });

    test('the daily cap counts the whole day, even across a page break', () {
      // Five minor debuts on one day: three are told, the first three.
      final day = DateTime(2026, 10, 20);
      final events = [
        for (var i = 0; i < 5; i++)
          _debut('cap-$i', at: day.add(Duration(hours: 9 + i)), rank: 150),
        _debut('older', at: DateTime(2026, 10, 18, 9), rank: 150),
        _debut('oldest', at: DateTime(2026, 10, 17, 9), rank: 150),
      ];

      return _controller(events: events, pageSize: 2).then((paged) {
        final titles = [
          for (final story in paged.controller.momentStories) story.facts.title,
        ];
        expect(titles, [
          'Song cap-2',
          'Song cap-1',
          'Song cap-0',
          'Song older',
          'Song oldest',
        ]);
      });
    });

    test('a failed page keeps the feed and can be tried again', () async {
      final paged = await _controller(events: _mixedHistory(), pageSize: 2);
      final before = paged.controller.momentStories.length;

      paged.moments.error = StateError('disk busy');
      await paged.controller.loadMoreMoments();

      expect(paged.controller.momentPageError, isA<StateError>());
      expect(paged.controller.momentStories, hasLength(before));

      paged.moments.error = null;
      await paged.controller.loadMoreMoments();

      expect(paged.controller.momentPageError, isNull);
      expect(
        paged.controller.momentStories.length,
        greaterThanOrEqualTo(before),
      );
    });
  });

  group('filters', () {
    test(
      'category and publisher narrow the feed; clearing shows it all',
      () async {
        final loaded = await _controller(events: _mixedHistory());
        final controller = loaded.controller;
        final all = controller.momentStories;

        controller.selectMomentCategory(MomentCategory.entries);
        expect(controller.visibleMomentStories, isNotEmpty);
        expect(
          controller.visibleMomentStories.map(
            (story) => MomentCategory.of(story.family),
          ),
          everyElement(MomentCategory.entries),
        );

        controller.selectMomentPublisher(MomentPublisher.sonusDaily);
        expect(
          controller.visibleMomentStories.map((story) => story.publisher),
          everyElement(MomentPublisher.sonusDaily),
        );

        controller
          ..selectMomentCategory(null)
          ..selectMomentPublisher(null);
        expect(controller.visibleMomentStories, all);
        expect(controller.isFilteringMoments, isFalse);
      },
    );
  });

  group('new-content dot', () {
    test(
      'shows for stories newer than the last visit, until Moments opens',
      () async {
        final store = MemoryMomentsLastSeenStore(DateTime.utc(2026, 10, 1));
        final loaded = await _controller(events: _mixedHistory(), store: store);
        final controller = loaded.controller;

        expect(controller.hasNewMoments, isTrue);

        controller.selectPresentationMode(ChartsPresentationMode.moments);
        await pumpEventQueue();

        expect(controller.hasNewMoments, isFalse);
        expect(store.seen, controller.momentStories.first.occurredAt.toUtc());

        controller.selectPresentationMode(ChartsPresentationMode.charts);
        expect(controller.hasNewMoments, isFalse);
      },
    );

    test('nothing newer than the last visit: no dot', () async {
      final store = MemoryMomentsLastSeenStore(DateTime.utc(2027));
      final loaded = await _controller(events: _mixedHistory(), store: store);

      expect(loaded.controller.hasNewMoments, isFalse);
      expect(store.writes, 0);
    });

    test('without a store there is never a dot', () async {
      final loaded = await _controller(events: _mixedHistory());

      expect(loaded.controller.hasNewMoments, isFalse);
    });
  });

  group('opening a song Moment', () {
    final when = DateTime(2026, 11, 3, 12);

    Future<MomentReleaseTarget?> open({
      required List<LibraryAlbumEdition> editions,
      String? playEdition,
      List<LibraryTrack>? tracks,
    }) async {
      final loaded = await _controller(
        events: [_debut('home', at: when, rank: 20, source: 'play-1')],
        tracks: tracks ?? [_track('home')],
        editions: editions,
        playEditions: {'play-1': ?playEdition},
      );
      final item = loaded.controller.momentStories.single.item;
      return loaded.controller.releaseTargetForMoment(item);
    }

    test('opens the edition the play was of while it survives', () async {
      final target = await open(
        editions: [_edition('primary', primary: true), _edition('deluxe')],
        playEdition: 'deluxe',
      );

      expect(target?.editionId, 'deluxe');
      expect(target?.editionRemoved, isFalse);
    });

    test('a removed edition opens the primary edition and says so', () async {
      final target = await open(
        editions: [_edition('primary', primary: true)],
        playEdition: 'deleted-deluxe',
      );

      expect(target?.editionId, 'primary');
      expect(target?.editionRemoved, isTrue);
    });

    test('without a recorded play it opens the song\'s own edition', () async {
      final target = await open(editions: [_edition('primary', primary: true)]);

      expect(target?.editionId, 'edition-album-1');
      expect(target?.editionRemoved, isFalse);
    });

    test('a purged song has no release link and no invented record', () async {
      final target = await open(editions: const [], tracks: const []);

      expect(target, isNull);
    });
  });

  group('covers and credits', () {
    test('SN-50 song stories show the song\'s own picture; earlier ones '
        'keep the primary cover', () async {
      final loaded = await _controller(
        events: [
          _debut('new', at: DateTime(2026, 11, 3, 12), rank: 20),
          _debut('old', at: DateTime(2026, 10, 20, 12), rank: 20),
        ],
        tracks: [
          _track('new', artworkPath: '/art/deluxe-new.jpg'),
          _track('old', artworkPath: '/art/deluxe-old.jpg'),
        ],
      );
      final byTitle = {
        for (final story in loaded.controller.momentStories)
          story.facts.title: story,
      };

      expect(byTitle['Song new']!.visual.left.path, '/art/deluxe-new.jpg');
      expect(byTitle['Song old']!.visual.left.path, '/art/primary.jpg');
    });

    test('SN-50 song stories name every performer; earlier stories and '
        'solo songs show no credit line', () async {
      final loaded = await _controller(
        events: [
          _debut('duet', at: DateTime(2026, 11, 3, 12), rank: 20),
          _debut('solo', at: DateTime(2026, 11, 3, 11), rank: 30),
          _debut('older', at: DateTime(2026, 10, 20, 12), rank: 20),
        ],
        tracks: [
          _track('duet', featured: const ['Bo Vale', 'Cy Rune']),
          _track('solo'),
          _track('older', featured: const ['Bo Vale']),
        ],
      );
      final credits = {
        for (final story in loaded.controller.momentStories)
          story.facts.title: loaded.controller.creditForMoment(story),
      };

      expect(credits['Song duet'], 'Ada Lune feat. Bo Vale, Cy Rune');
      expect(credits['Song solo'], isNull);
      expect(credits['Song older'], isNull);
    });
  });
}

/// What a reader sees of each story.
List<String> _summary(List<MomentStory> stories) => [
  for (final story in stories)
    '${story.id}|${story.publisher.name}|${story.headline}|${story.body}',
];

/// Days of real-time debuts before and after the SN-50 rules, several per
/// day so the daily cap and headline variety both apply.
List<ChartMomentEvent> _mixedHistory() => [
  for (final day in [
    DateTime(2026, 10, 29),
    DateTime(2026, 10, 30),
    DateTime(2026, 10, 31),
    DateTime(2026, 11, 1),
    DateTime(2026, 11, 2),
    DateTime(2026, 11, 4),
  ])
    for (var i = 0; i < 5; i++)
      _debut(
        '${day.month}-${day.day}-$i',
        at: day.add(Duration(hours: 8 + i)),
        rank: i.isEven ? 150 : 12 + i,
      ),
];

ChartMomentEvent _debut(
  String id, {
  required DateTime at,
  required int rank,
  String? source,
}) {
  final week = DateTime.utc(2026, 10, 25);
  final song = ChartEntitySnapshot(
    entityId: 'song-$id',
    title: 'Song $id',
    artistId: 'artist-1',
    artistName: 'Ada Lune',
    albumTitle: 'Album One',
  );

  return ChartMomentEvent(
    id: 'debut-$id',
    deduplicationKey: 'debut-$id',
    sourceId: source ?? 'play-$id',
    chartType: ChartType.songs,
    scope: ChartMomentScope.allTime,
    eventType: ChartMomentEventType.debut,
    entity: song,
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: at.toUtc(),
    createdAt: at.toUtc(),
    currentRank: rank,
    currentPeakRank: rank,
    qualifiedStreamCount: 1,
  );
}

LibraryTrack _track(
  String id, {
  String? artworkPath,
  List<String> featured = const [],
}) => LibraryTrack(
  songId: 'song-$id',
  title: 'Song $id',
  artistId: 'artist-1',
  artistName: 'Ada Lune',
  albumId: 'album-1',
  albumTitle: 'Album One',
  albumEditionId: 'edition-album-1',
  albumEditionTitle: 'Album One',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: featured,
  dateAdded: DateTime.utc(2026, 9, 1),
  isAvailable: true,
  filePath: 'C:/Music/$id.mp3',
  artworkPath: artworkPath,
);

LibraryAlbumEdition _edition(String id, {bool primary = false}) =>
    LibraryAlbumEdition(
      editionId: id,
      albumId: 'album-1',
      title: primary ? 'Album One' : 'Album One (Deluxe)',
      type: primary ? AlbumEditionType.standard : AlbumEditionType.deluxe,
      isPrimary: primary,
      dateAdded: DateTime.utc(2026, 9, 1),
    );

Future<({ChartsController controller, _PagedMoments moments})> _controller({
  required List<ChartMomentEvent> events,
  int pageSize = 200,
  MomentsLastSeenStore? store,
  List<LibraryTrack>? tracks,
  List<LibraryAlbumEdition> editions = const [],
  Map<String, String> playEditions = const {},
}) async {
  final moments = _PagedMoments(events);
  final controller = ChartsController(
    allTimeCharts: _EmptyAllTimeCharts(),
    finalization: _NoFinalization(),
    charts: _NoHistory(),
    library: _EditionLibrary(
      tracks: tracks ?? const [],
      albums: [
        LibraryAlbum(
          albumId: 'album-1',
          title: 'Album One',
          artistId: 'artist-1',
          artistName: 'Ada Lune',
          trackCount: 1,
          dateAdded: DateTime.utc(2026, 9, 1),
          artworkPath: '/art/primary.jpg',
          primaryEditionId: 'primary',
        ),
      ],
      editions: editions,
    ),
    moments: moments,
    now: () => DateTime(2026, 11, 5, 12),
    momentsLastSeen: store,
    playEdition: (playId) async => playEditions[playId],
    momentPageSize: pageSize,
  );
  addTearDown(controller.dispose);

  await controller.load();
  await pumpEventQueue();

  return (controller: controller, moments: moments);
}

class _PagedMoments implements ChartMomentRepository {
  _PagedMoments(this.events);

  final List<ChartMomentEvent> events;
  Object? error;
  int pageReads = 0;

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async {
    pageReads++;
    final error = this.error;
    if (error != null) throw error;
    return momentPageOf(events, before: before, limit: limit);
  }

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

class _EditionLibrary extends FakeChartLibrary
    implements AlbumEditionQueryRepository {
  _EditionLibrary({
    required super.tracks,
    required super.albums,
    required this.editions,
  });

  final List<LibraryAlbumEdition> editions;

  @override
  Future<List<LibraryAlbumEdition>> getAlbumEditions(String albumId) async => [
    for (final edition in editions)
      if (edition.albumId == albumId) edition,
  ];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumEditionId(String editionId) =>
      throw UnimplementedError();
}

class _EmptyAllTimeCharts implements AllTimeChartService {
  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async => AllTimeChart(
    chartType: chartType,
    comparisonStartUtc: DateTime.utc(2026, 10, 25),
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
