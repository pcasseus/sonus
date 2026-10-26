import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_moment_service.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/presentation/models/charts_presentation_mode.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';

import '../../support/all_time_chart_fakes.dart' as support;

void main() {
  final referenceLocal = DateTime(2026, 9, 28, 12);

  test('loads the all-time songs chart and finalized history', () async {
    final live = _snapshot(
      id: 'live-songs',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    final history = [
      _snapshot(
        id: 'songs-previous',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 20),
        finalized: true,
      ),
    ];

    final allTimeCharts = _FakeAllTimeChartService(snapshot: live);
    final finalization = _FakeChartFinalizationService();
    final charts = _FakeChartRepository(
      historyByType: {ChartType.songs: history},
    );

    final controller = ChartsController(
      allTimeCharts: allTimeCharts,
      finalization: finalization,
      charts: charts,
      library: _FakeLibraryQueryRepository(),
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.chartType, ChartType.songs);
    expect(controller.viewSize, ChartViewSize.top100);
    expect(controller.allTimeChart?.entries, same(live.entries));
    expect(controller.entries, same(live.entries));
    expect(controller.snapshot, isNull);
    expect(controller.history, history);
    expect(controller.isViewingAllTime, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);

    expect(finalization.callCount, 1);
    expect(finalization.lastReferenceLocal, referenceLocal);

    expect(allTimeCharts.callCount, 1);
    expect(allTimeCharts.lastChartType, ChartType.songs);
    expect(allTimeCharts.lastViewSize, ChartViewSize.top100);
  });

  test(
    'switching to albums reloads albums data without finalizing again',
    () async {
      final allTimeCharts = _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live-songs',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
        snapshotsByType: {
          ChartType.albums: _snapshot(
            id: 'live-albums',
            chartType: ChartType.albums,
            weekStartUtc: DateTime.utc(2026, 9, 27),
          ),
        },
      );

      final finalization = _FakeChartFinalizationService();

      final charts = _FakeChartRepository(
        historyByType: {
          ChartType.albums: [
            _snapshot(
              id: 'albums-history',
              chartType: ChartType.albums,
              weekStartUtc: DateTime.utc(2026, 9, 20),
              finalized: true,
            ),
          ],
        },
      );

      final controller = ChartsController(
        allTimeCharts: allTimeCharts,
        finalization: finalization,
        charts: charts,
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );

      await controller.load();
      await controller.selectChartType(ChartType.albums);

      expect(controller.chartType, ChartType.albums);
      expect(controller.allTimeChart?.chartType, ChartType.albums);
      expect(controller.history.single.chartType, ChartType.albums);

      expect(finalization.callCount, 1);
      expect(allTimeCharts.callCount, 2);
    },
  );

  test(
    'view size reloads the all-time chart with the selected limit',
    () async {
      final allTimeCharts = _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      );

      final controller = ChartsController(
        allTimeCharts: allTimeCharts,
        finalization: _FakeChartFinalizationService(),
        charts: _FakeChartRepository(),
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );

      await controller.load();
      await controller.selectViewSize(ChartViewSize.top25);

      expect(controller.viewSize, ChartViewSize.top25);
      expect(allTimeCharts.lastViewSize, ChartViewSize.top25);
      expect(allTimeCharts.callCount, 2);
    },
  );

  test(
    'history navigation moves from all time to older weeks and back',
    () async {
      final history = [
        _snapshot(
          id: 'week-1',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
        _snapshot(
          id: 'week-2',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 13),
          finalized: true,
        ),
      ];

      final controller = ChartsController(
        allTimeCharts: _FakeAllTimeChartService(
          snapshot: _snapshot(
            id: 'live',
            chartType: ChartType.songs,
            weekStartUtc: DateTime.utc(2026, 9, 27),
          ),
        ),
        finalization: _FakeChartFinalizationService(),
        charts: _FakeChartRepository(historyByType: {ChartType.songs: history}),
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );

      await controller.load();

      controller.showOlderWeek();

      expect(controller.selectedHistoricalSnapshot?.id, 'week-1');

      controller.showOlderWeek();

      expect(controller.selectedHistoricalSnapshot?.id, 'week-2');

      controller.showNewerWeek();

      expect(controller.selectedHistoricalSnapshot?.id, 'week-1');

      controller.showNewerWeek();

      expect(controller.isViewingAllTime, isTrue);
    },
  );

  test('selectHistoricalWeek jumps directly to an available week', () async {
    final target = _snapshot(
      id: 'target',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 8, 30),
      finalized: true,
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(
        historyByType: {
          ChartType.songs: [
            _snapshot(
              id: 'newer',
              chartType: ChartType.songs,
              weekStartUtc: DateTime.utc(2026, 9, 20),
              finalized: true,
            ),
            target,
          ],
        },
      ),
      library: _FakeLibraryQueryRepository(),
      now: () => referenceLocal,
    );

    await controller.load();

    final found = controller.selectHistoricalWeek(target.weekStartUtc);

    expect(found, isTrue);
    expect(controller.selectedHistoricalSnapshot, same(target));
  });

  test('historical view applies selected chart size locally', () async {
    final entries = List.generate(40, (index) => _entry(index + 1));

    final history = _snapshot(
      id: 'history',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 20),
      finalized: true,
      entries: entries,
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(
        historyByType: {
          ChartType.songs: [history],
        },
      ),
      library: _FakeLibraryQueryRepository(),
      now: () => referenceLocal,
    );

    await controller.load();

    controller.showOlderWeek();
    await controller.selectViewSize(ChartViewSize.top25);

    expect(controller.snapshot?.entries.length, 25);
  });

  test('loads raw Moments and exposes aggregated feed items', () async {
    final entity = ChartEntitySnapshot(
      entityId: 'song-a',
      title: 'Song A',
      artistId: 'artist-a',
      artistName: 'Artist A',
      albumTitle: 'Album A',
    );

    final moments = _FakeChartMomentRepository(
      events: [
        _momentEvent(
          id: 'rise',
          type: ChartMomentEventType.rankRise,
          entity: entity,
          previousRank: 15,
          currentRank: 3,
        ),
        _momentEvent(
          id: 'peak',
          type: ChartMomentEventType.newPeak,
          entity: entity,
          previousRank: 15,
          currentRank: 3,
        ),
      ],
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      moments: moments,
      now: () => referenceLocal,
    );

    await controller.load();

    expect(moments.getRecentCallCount, 1);
    expect(moments.lastLimit, isNull);

    expect(controller.hasMomentFeedError, isFalse);
    expect(controller.hasMomentFeedItems, isTrue);
    expect(controller.momentFeedItems, hasLength(1));

    final item = controller.momentFeedItems.single;

    expect(item.events, hasLength(2));
    expect(item.dominantEventType, ChartMomentEventType.newPeak);
  });

  test('refresh reloads Moments after finalization', () async {
    final moments = _FakeChartMomentRepository();

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      moments: moments,
      now: () => referenceLocal,
    );

    await controller.load();
    await controller.refresh();

    expect(moments.getRecentCallCount, 2);
  });

  test('Moments read failure does not fail chart loading', () async {
    final moments = _FakeChartMomentRepository(
      error: StateError('Moments failed'),
    );

    final live = _snapshot(
      id: 'live',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(snapshot: live),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      moments: moments,
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.allTimeChart?.entries, same(live.entries));

    expect(controller.hasError, isFalse);
    expect(controller.isLoading, isFalse);

    expect(controller.hasMomentFeedError, isTrue);
    expect(controller.momentFeedError, isA<StateError>());
    expect(controller.momentFeedItems, isEmpty);
  });
  test('all-time Moments are recorded before the feed is read', () async {
    final log = <String>[];
    final moments = _FakeChartMomentRepository(onRead: () => log.add('read'));
    final allTimeMoments = _FakeAllTimeMomentService(
      onRecord: () => log.add('record'),
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      moments: moments,
      allTimeMoments: allTimeMoments,
      now: () => referenceLocal,
    );

    await controller.load();
    await controller.refresh();

    expect(log, ['record', 'read', 'record', 'read']);
    expect(allTimeMoments.lastReferenceLocal, referenceLocal);
  });

  test('an all-time Moments failure does not fail the chart', () async {
    final live = _snapshot(
      id: 'live',
      chartType: ChartType.songs,
      weekStartUtc: DateTime.utc(2026, 9, 27),
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(snapshot: live),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      moments: _FakeChartMomentRepository(),
      allTimeMoments: _FakeAllTimeMomentService(
        error: StateError('replay failed'),
      ),
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.allTimeChart?.entries, same(live.entries));
    expect(controller.hasError, isFalse);
    expect(controller.momentFeedError, isA<StateError>());
  });

  test(
    'presentation mode defaults to charts and switches without reloading',
    () async {
      final allTimeCharts = _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      );

      final controller = ChartsController(
        allTimeCharts: allTimeCharts,
        finalization: _FakeChartFinalizationService(),
        charts: _FakeChartRepository(),
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );

      await controller.load();

      expect(controller.presentationMode, ChartsPresentationMode.charts);
      expect(controller.isShowingCharts, isTrue);
      expect(controller.isShowingMoments, isFalse);

      final chartLoadCount = allTimeCharts.callCount;

      controller.selectPresentationMode(ChartsPresentationMode.moments);

      expect(controller.presentationMode, ChartsPresentationMode.moments);
      expect(controller.isShowingCharts, isFalse);
      expect(controller.isShowingMoments, isTrue);
      expect(allTimeCharts.callCount, chartLoadCount);

      controller.selectPresentationMode(ChartsPresentationMode.charts);

      expect(controller.presentationMode, ChartsPresentationMode.charts);
      expect(controller.isShowingCharts, isTrue);
      expect(controller.isShowingMoments, isFalse);
      expect(allTimeCharts.callCount, chartLoadCount);
    },
  );

  test('resolves mixed song and album Moment artwork from one load', () async {
    final songEntity = ChartEntitySnapshot(
      entityId: 'song-art',
      title: 'Song Art',
      artistId: 'artist-a',
      artistName: 'Artist A',
      albumTitle: 'Album Art',
    );

    final albumEntity = ChartEntitySnapshot(
      entityId: 'album-art',
      title: 'Album Art',
      artistId: 'artist-a',
      artistName: 'Artist A',
      albumTitle: 'Album Art',
    );

    final moments = _FakeChartMomentRepository(
      events: [
        _momentEvent(
          id: 'song-moment',
          type: ChartMomentEventType.newPeak,
          entity: songEntity,
          chartType: ChartType.songs,
          currentRank: 3,
        ),
        _momentEvent(
          id: 'album-moment',
          type: ChartMomentEventType.newPeak,
          entity: albumEntity,
          chartType: ChartType.albums,
          currentRank: 2,
        ),
      ],
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(
        tracks: [
          _libraryTrack(
            songId: 'song-art',
            artworkPath: 'C:/Artwork/song-art.jpg',
          ),
        ],
        albums: [
          _libraryAlbum(
            albumId: 'album-art',
            artworkPath: 'C:/Artwork/album-art.jpg',
          ),
        ],
      ),
      moments: moments,
      now: () => referenceLocal,
    );

    await controller.load();

    final songItem = controller.momentFeedItems.singleWhere(
      (item) => item.chartType == ChartType.songs,
    );

    final albumItem = controller.momentFeedItems.singleWhere(
      (item) => item.chartType == ChartType.albums,
    );

    expect(
      controller.artworkPathForMoment(songItem),
      'C:/Artwork/song-art.jpg',
    );

    expect(
      controller.artworkPathForMoment(albumItem),
      'C:/Artwork/album-art.jpg',
    );
  });

  test('missing related Moment entity artwork resolves to null', () async {
    final primary = ChartEntitySnapshot(
      entityId: 'song-primary',
      title: 'Primary Song',
      artistId: 'artist-a',
      artistName: 'Artist A',
      albumTitle: 'Album A',
    );

    final related = ChartEntitySnapshot(
      entityId: 'song-missing',
      title: 'Missing Song',
      artistId: 'artist-a',
      artistName: 'Artist A',
      albumTitle: 'Album A',
    );

    final at = DateTime.utc(2026, 9, 28, 12);

    final moments = _FakeChartMomentRepository(
      events: [
        ChartMomentEvent(
          id: 'related-moment',
          deduplicationKey: 'related-moment',
          sourceId: 'snapshot-1',
          chartType: ChartType.songs,
          scope: ChartMomentScope.finalized,
          eventType: ChartMomentEventType.artistReturnsToNumberOneSong,
          entity: primary,
          relatedEntity: related,
          weekStartUtc: DateTime.utc(2026, 9, 27),
          weekEndUtc: DateTime.utc(2026, 10, 4),
          occurredAt: at,
          createdAt: at,
          currentRank: 1,
          threshold: 1,
          milestoneValue: 6,
        ),
      ],
    );

    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(
        tracks: [
          _libraryTrack(
            songId: 'song-primary',
            artworkPath: 'C:/Artwork/primary.jpg',
          ),
        ],
      ),
      moments: moments,
      now: () => referenceLocal,
    );

    await controller.load();

    final item = controller.momentFeedItems.single;

    expect(controller.artworkPathForMoment(item), 'C:/Artwork/primary.jpg');

    expect(controller.relatedArtworkPathForMoment(item), isNull);
  });
  test('captures loading failures', () async {
    final controller = ChartsController(
      allTimeCharts: _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'unused',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
        error: StateError('Chart failed'),
      ),
      finalization: _FakeChartFinalizationService(),
      charts: _FakeChartRepository(),
      library: _FakeLibraryQueryRepository(),
      now: () => referenceLocal,
    );

    await controller.load();

    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
    expect(controller.isLoading, isFalse);
  });

  group('permanent Hot 100', () {
    // Regression: the Hot 100 was the live weekly chart, so last week's #1
    // vanished at the week boundary until it was played again.
    final lastWeek = DateTime(2026, 9, 21, 12).toUtc();
    final plays = [
      ...support.qualifiedPlays('angel', 'album-angel', 43, lastWeek),
      ...support.qualifiedPlays('bitter', 'album-bitter', 36, lastWeek),
    ];
    final library = support.FakeChartLibrary(
      tracks: [
        support.libraryTrack('angel', 'album-angel'),
        support.libraryTrack('bitter', 'album-bitter'),
      ],
      albums: [
        support.libraryAlbum('album-angel'),
        support.libraryAlbum('album-bitter'),
      ],
    );

    ChartsController controllerWith({List<ChartSnapshot> history = const []}) {
      return ChartsController(
        allTimeCharts: AllTimeChartService(
          qualifiedPlays: support.FakeQualifiedPlayRepository(plays),
          library: library,
        ),
        finalization: _FakeChartFinalizationService(),
        charts: _FakeChartRepository(historyByType: {ChartType.songs: history}),
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );
    }

    test("last week's #1 is still #1 with no listening this week", () async {
      final controller = controllerWith();

      await controller.load();

      expect(controller.isViewingAllTime, isTrue);
      expect(controller.entries.map((e) => e.entity.entityId), [
        'angel',
        'bitter',
      ]);
      expect(controller.entries.first.qualifiedStreamCount, 43);
    });

    test('albums use the same lifetime totals', () async {
      final controller = controllerWith();

      await controller.load();
      await controller.selectChartType(ChartType.albums);

      expect(controller.entries.map((e) => e.entity.entityId), [
        'album-angel',
        'album-bitter',
      ]);
    });

    test('finalized weekly charts stay browsable as history', () async {
      final finalized = _snapshot(
        id: 'week',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 20),
        finalized: true,
      );
      final controller = controllerWith(history: [finalized]);

      await controller.load();
      controller.showOlderWeek();

      expect(controller.isViewingAllTime, isFalse);
      expect(controller.snapshot?.id, 'week');
      expect(controller.entries, same(finalized.entries));

      controller.showNewerWeek();

      expect(controller.isViewingAllTime, isTrue);
      expect(controller.entries.first.entity.entityId, 'angel');
    });

    test('weekly chart peaks come from finalized weeks only', () async {
      ChartSnapshot week(DateTime start, String id, int rank) => _snapshot(
        id: id,
        chartType: ChartType.songs,
        weekStartUtc: start,
        finalized: true,
        entries: [
          ChartEntry(
            entity: ChartEntitySnapshot(
              entityId: 'angel',
              title: 'Angel',
              artistName: 'A',
            ),
            rank: rank,
            qualifiedStreamCount: 5,
            lastQualifiedAt: start,
            peakRank: rank,
            peakAchievedAt: start,
            weeksOnChart: 1,
            movement: ChartMovement.newEntry,
          ),
        ],
      );
      final controller = controllerWith(
        history: [
          week(DateTime.utc(2026, 9, 20), 'w2', 4),
          week(DateTime.utc(2026, 9, 13), 'w1', 2),
          // An extended standing is not a weekly chart position.
          week(DateTime.utc(2026, 9, 6), 'w0', 150),
        ],
      );

      await controller.load();

      final angel = controller.entries.firstWhere(
        (e) => e.entity.entityId == 'angel',
      );
      final bitter = controller.entries.firstWhere(
        (e) => e.entity.entityId == 'bitter',
      );
      expect(controller.weeklyPeakFor(angel), 2);
      expect(controller.weeklyPeakFor(bitter), isNull);
    });
  });

  group('load lifecycle', () {
    late _FakeChartFinalizationService finalization;
    late _FakeAllTimeChartService allTimeCharts;
    late ChartsController controller;

    setUp(() {
      finalization = _FakeChartFinalizationService();
      allTimeCharts = _FakeAllTimeChartService(
        snapshot: _snapshot(
          id: 'live',
          chartType: ChartType.songs,
          weekStartUtc: DateTime.utc(2026, 9, 27),
        ),
      );
      controller = ChartsController(
        allTimeCharts: allTimeCharts,
        finalization: finalization,
        charts: _FakeChartRepository(),
        library: _FakeLibraryQueryRepository(),
        now: () => referenceLocal,
      );
    });

    // Regression: refresh() did not check for an in-flight load, so a
    // pull-to-refresh during the first load ran a second, concurrent
    // finalization pass.
    test(
      'refresh during a load joins it instead of finalizing again',
      () async {
        finalization.gate = Completer<void>();

        final loading = controller.load();
        final refreshing = controller.refresh();

        finalization.gate!.complete();
        await Future.wait([loading, refreshing]);

        expect(finalization.callCount, 1);
        expect(finalization.maxConcurrent, 1);
        expect(controller.allTimeChart, isNotNull);
        expect(controller.isLoading, isFalse);
      },
    );

    test('repeated refreshes during a load share one pass', () async {
      finalization.gate = Completer<void>();

      final pending = [
        controller.load(),
        controller.refresh(),
        controller.refresh(),
      ];

      finalization.gate!.complete();
      await Future.wait(pending);

      expect(finalization.callCount, 1);
    });

    test('refresh after a load has finished finalizes again', () async {
      await controller.load();
      await controller.refresh();

      expect(finalization.callCount, 2);
      expect(finalization.maxConcurrent, 1);
    });

    test('load during a load waits for its result', () async {
      finalization.gate = Completer<void>();

      final first = controller.load();
      final second = controller.load();
      var secondDone = false;
      unawaited(second.then((_) => secondDone = true));

      await Future<void>.delayed(Duration.zero);
      expect(secondDone, isFalse);

      finalization.gate!.complete();
      await Future.wait([first, second]);

      expect(finalization.callCount, 1);
      expect(controller.allTimeChart, isNotNull);
    });

    // Regression: a load still in flight when the controller was disposed
    // called notifyListeners() on the disposed notifier and kept loading.
    test('disposing during a load stops it without notifying', () async {
      finalization.gate = Completer<void>();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final loading = controller.load();
      final notificationsBeforeDispose = notifications;
      controller.dispose();

      finalization.gate!.complete();
      await loading;

      expect(notifications, notificationsBeforeDispose);
      expect(allTimeCharts.callCount, 0);
    });

    test('calls after dispose do nothing and do not throw', () async {
      controller.dispose();

      await controller.load();
      await controller.refresh();
      await controller.selectChartType(ChartType.albums);
      await controller.selectViewSize(ChartViewSize.top10);
      controller.selectPresentationMode(ChartsPresentationMode.moments);
      controller.showOlderWeek();
      controller.showNewerWeek();
      controller.showAllTime();

      expect(finalization.callCount, 0);
      expect(allTimeCharts.callCount, 0);
    });
  });
}

ChartMomentEvent _momentEvent({
  required String id,
  required ChartMomentEventType type,
  required ChartEntitySnapshot entity,
  ChartType chartType = ChartType.songs,
  int? previousRank,
  int? currentRank,
}) {
  final occurredAt = DateTime.utc(2026, 9, 28, 12);

  return ChartMomentEvent(
    id: id,
    deduplicationKey: id,
    sourceId: 'snapshot-1',
    chartType: chartType,
    scope: ChartMomentScope.finalized,
    eventType: type,
    entity: entity,
    weekStartUtc: DateTime.utc(2026, 9, 27),
    weekEndUtc: DateTime.utc(2026, 10, 4),
    occurredAt: occurredAt,
    createdAt: occurredAt,
    previousRank: previousRank,
    currentRank: currentRank,
  );
}

ChartSnapshot _snapshot({
  required String id,
  required ChartType chartType,
  required DateTime weekStartUtc,
  bool finalized = false,
  List<ChartEntry>? entries,
}) {
  return ChartSnapshot(
    id: id,
    chartType: chartType,
    weekStartUtc: weekStartUtc,
    weekEndUtc: weekStartUtc.add(const Duration(days: 7)),
    finalizedAt: finalized ? weekStartUtc.add(const Duration(days: 7)) : null,
    entries: entries ?? [_entry(1)],
  );
}

ChartEntry _entry(int rank) {
  return ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: 'song_$rank',
      title: 'Song $rank',
      artistName: 'Artist $rank',
      albumTitle: 'Album $rank',
    ),
    rank: rank,
    qualifiedStreamCount: 101 - rank,
    lastQualifiedAt: DateTime.utc(2026, 9, 27, 12),
    previousFinalRank: rank == 1 ? 3 : rank,
    peakRank: 1,
    peakAchievedAt: DateTime.utc(2026, 9, 20),
    weeksOnChart: 4,
    movement: rank == 1 ? ChartMovement.up : ChartMovement.same,
  );
}

LibraryTrack _libraryTrack({required String songId, String? artworkPath}) {
  return LibraryTrack(
    songId: songId,
    title: 'Song $songId',
    artistId: 'artist-a',
    artistName: 'Artist A',
    albumId: 'album-a',
    albumTitle: 'Album A',
    albumEditionId: 'edition-a',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: true,
    isSongBlocked: false,
    filePath: 'C:/Music/$songId.mp3',
    artworkPath: artworkPath,
  );
}

LibraryAlbum _libraryAlbum({required String albumId, String? artworkPath}) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Album $albumId',
    artistId: 'artist-a',
    artistName: 'Artist A',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
    artworkPath: artworkPath,
  );
}

/// Serves each given snapshot's entries as the all-time chart.
class _FakeAllTimeChartService implements AllTimeChartService {
  _FakeAllTimeChartService({
    required this.snapshot,
    this.snapshotsByType = const {},
    this.error,
  });

  ChartSnapshot snapshot;
  final Map<ChartType, ChartSnapshot> snapshotsByType;
  Object? error;

  int callCount = 0;
  ChartType? lastChartType;
  ChartViewSize? lastViewSize;
  DateTime? lastReferenceLocal;

  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async {
    callCount++;
    lastChartType = chartType;
    lastViewSize = viewSize;
    lastReferenceLocal = referenceLocal;

    final error = this.error;

    if (error != null) {
      throw error;
    }

    final source = snapshotsByType[chartType] ?? snapshot;

    return AllTimeChart(
      chartType: source.chartType,
      comparisonStartUtc: source.weekStartUtc,
      entries: source.entries,
    );
  }
}

class _FakeChartFinalizationService implements ChartFinalizationService {
  int callCount = 0;
  DateTime? lastReferenceLocal;

  /// When set, each pass waits for it, so tests can hold a load in flight.
  Completer<void>? gate;

  int _active = 0;
  int maxConcurrent = 0;

  @override
  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async {
    callCount++;
    lastReferenceLocal = referenceLocal;
    _active++;
    maxConcurrent = math.max(maxConcurrent, _active);

    try {
      await gate?.future;
    } finally {
      _active--;
    }

    return const [];
  }

  @override
  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) {
    throw UnimplementedError();
  }
}

class _FakeChartMomentRepository implements ChartMomentRepository {
  _FakeChartMomentRepository({this.events = const [], this.error, this.onRead});

  final List<ChartMomentEvent> events;
  final Object? error;
  final void Function()? onRead;

  int getRecentCallCount = 0;
  int? lastLimit;

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async {
    getRecentCallCount++;
    lastLimit = limit;
    onRead?.call();

    final error = this.error;

    if (error != null) {
      throw error;
    }

    if (limit == null || events.length <= limit) {
      return List<ChartMomentEvent>.unmodifiable(events);
    }

    return List<ChartMomentEvent>.unmodifiable(events.take(limit));
  }

  @override
  Future<ChartMomentEvent?> getById(String id) async {
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }

    return null;
  }

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {}

  @override
  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async {}
}

class _FakeAllTimeMomentService implements AllTimeMomentService {
  _FakeAllTimeMomentService({this.onRecord, this.error});

  final void Function()? onRecord;
  final Object? error;
  DateTime? lastReferenceLocal;

  @override
  Future<List<ChartMomentEvent>> record({
    required DateTime referenceLocal,
  }) async {
    lastReferenceLocal = referenceLocal;
    onRecord?.call();
    final error = this.error;
    if (error != null) throw error;
    return const [];
  }
}

class _FakeChartRepository implements ChartRepository {
  _FakeChartRepository({this.historyByType = const {}});

  final Map<ChartType, List<ChartSnapshot>> historyByType;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final values = historyByType[chartType] ?? const [];

    if (limit == null || values.length <= limit) {
      return values;
    }

    return values.take(limit).toList(growable: false);
  }

  @override
  Future<ChartSnapshot?> getById(String id) async => null;

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    return null;
  }

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {}
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({this.tracks = const [], this.albums = const []});

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    for (final track in tracks) {
      if (track.songId == songId) {
        return track;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return albums.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    for (final album in albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }
}
