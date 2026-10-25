import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';

import '../../support/all_time_chart_fakes.dart';

/// Local times: week 1 starts Sunday 4 Oct, week 2 on Sunday 11 Oct.
final lastWeek = DateTime(2026, 10, 5, 12).toUtc();
final thisWeek = DateTime(2026, 10, 12, 12).toUtc();
final reference = DateTime(2026, 10, 13, 9);
final lateLastWeek = DateTime(2026, 10, 9, 12).toUtc();

void main() {
  AllTimeChartService service({
    required FakeQualifiedPlayRepository plays,
    FakeChartLibrary? library,
  }) {
    return AllTimeChartService(
      qualifiedPlays: plays,
      library:
          library ??
          FakeChartLibrary(
            tracks: [
              for (final id in ['angel', 'bitter', 'fresh'])
                libraryTrack(id, 'album-$id'),
            ],
            albums: [
              for (final id in ['angel', 'bitter', 'fresh'])
                libraryAlbum('album-$id'),
            ],
          ),
    );
  }

  final history = [
    ...qualifiedPlays('angel', 'album-angel', 43, lastWeek),
    ...qualifiedPlays('bitter', 'album-bitter', 36, lastWeek),
  ];

  test(
    'characterization: the weekly chart restarts at the week boundary',
    () async {
      // The old Hot 100 was this live weekly chart. With no listening yet this
      // week, last week's #1 disappears; this is the behaviour being replaced.
      final weekly = ChartSnapshotBuilderService(
        qualifiedPlays: FakeQualifiedPlayRepository(history),
        library: FakeChartLibrary(tracks: const [], albums: const []),
        charts: _EmptyChartRepository(),
      );

      final snapshot = await weekly.build(
        chartType: ChartType.songs,
        weekStartUtc: DateTime(2026, 10, 11).toUtc(),
        weekEndUtc: DateTime(2026, 10, 18).toUtc(),
      );

      expect(snapshot.entries, isEmpty);
    },
  );

  _statsTests(service, history);

  test('a #1 stays #1 after a week boundary with no new listening', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository(history),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    expect(chart.entries.map((e) => e.entity.entityId), ['angel', 'bitter']);
    expect(chart.entries.map((e) => e.qualifiedStreamCount), [43, 36]);
    expect(chart.entries.first.movement, ChartMovement.same);
    expect(chart.entries.first.previousFinalRank, 1);
  });

  test('this week\'s plays add to lifetime totals', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository([
        ...history,
        ...qualifiedPlays('bitter', 'album-bitter', 8, thisWeek),
        ...qualifiedPlays('fresh', 'album-fresh', 1, thisWeek),
      ]),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    final byId = {for (final e in chart.entries) e.entity.entityId: e};
    expect(chart.entries.first.entity.entityId, 'bitter');
    expect(byId['bitter']!.qualifiedStreamCount, 44);
    expect(byId['bitter']!.movement, ChartMovement.up);
    expect(byId['angel']!.movement, ChartMovement.down);
    expect(byId['fresh']!.movement, ChartMovement.newEntry);
    expect(chart.comparisonStartUtc, DateTime(2026, 10, 11).toUtc());
  });

  test('weeks on chart is not claimed by the all-time chart', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository(history),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    expect(chart.entries.map((e) => e.weeksOnChart), everyElement(0));
  });

  test('blocked and removed songs are left out', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository([
        ...history,
        ...qualifiedPlays('gone', 'album-gone', 99, lastWeek),
      ]),
      library: FakeChartLibrary(
        tracks: [
          libraryTrack('angel', 'album-angel', blocked: true),
          libraryTrack('bitter', 'album-bitter'),
        ],
        albums: const [],
      ),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    expect(chart.entries.map((e) => e.entity.entityId), ['bitter']);
    expect(chart.entries.single.rank, 1);
  });

  group('albums', () {
    test('ranks albums by lifetime plays of their songs', () async {
      final chart = await service(
        plays: FakeQualifiedPlayRepository(history),
      ).load(chartType: ChartType.albums, referenceLocal: reference);

      expect(chart.entries.map((e) => e.entity.entityId), [
        'album-angel',
        'album-bitter',
      ]);
      expect(chart.entries.map((e) => e.qualifiedStreamCount), [43, 36]);
    });

    test(
      'Standard and Deluxe plays count once each toward one album',
      () async {
        final chart = await service(
          plays: FakeQualifiedPlayRepository([
            ...qualifiedPlays(
              'track1',
              'album-x',
              3,
              lastWeek,
              albumEditionId: 'x-standard',
            ),
            // The same song, shared by both editions, played from the Deluxe.
            ...qualifiedPlays(
              'track1',
              'album-x',
              2,
              thisWeek,
              albumEditionId: 'x-deluxe',
            ),
            ...qualifiedPlays(
              'bonus',
              'album-x',
              1,
              thisWeek.add(const Duration(hours: 1)),
              albumEditionId: 'x-deluxe',
            ),
          ]),
          library: FakeChartLibrary(
            tracks: const [],
            albums: [libraryAlbum('album-x')],
          ),
        ).load(chartType: ChartType.albums, referenceLocal: reference);

        expect(chart.entries.single.entity.entityId, 'album-x');
        expect(chart.entries.single.qualifiedStreamCount, 6);
      },
    );
  });

  test('the Top 200 uses the same lifetime basis and ordering', () async {
    final tracks = [
      for (var i = 0; i < 205; i++) libraryTrack('s$i', 'album-s$i'),
    ];
    final plays = [
      for (var i = 0; i < 205; i++)
        ...qualifiedPlays('s$i', 'album-s$i', 205 - i, lastWeek),
    ];
    final library = FakeChartLibrary(tracks: tracks, albums: const []);

    final top100 = await service(
      plays: FakeQualifiedPlayRepository(plays),
      library: library,
    ).load(chartType: ChartType.songs, referenceLocal: reference);
    final top200 =
        await service(
          plays: FakeQualifiedPlayRepository(plays),
          library: library,
        ).load(
          chartType: ChartType.songs,
          referenceLocal: reference,
          viewSize: ChartViewSize.top200,
        );

    expect(top100.entries, hasLength(100));
    expect(top200.entries, hasLength(200));
    expect(
      top200.entries.take(100).map((e) => e.entity.entityId),
      top100.entries.map((e) => e.entity.entityId),
    );
    expect(top200.entries[150].qualifiedStreamCount, 205 - 150);
  });

  test('reads the play history once per load', () async {
    final plays = FakeQualifiedPlayRepository(history);

    await service(
      plays: plays,
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    expect(plays.getAllCalls, 1);
  });

  test('no listening gives an empty chart', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository(const []),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    expect(chart.entries, isEmpty);
  });
}

void _statsTests(
  AllTimeChartService Function({required FakeQualifiedPlayRepository plays})
  service,
  List<QualifiedPlay> history,
) {
  group('weekly change', () {
    test('compares this week so far with the same time last week', () async {
      final chart = await service(
        plays: FakeQualifiedPlayRepository([
          ...history,
          // Later last week than now is into this week: not compared.
          ...qualifiedPlays('bitter', 'album-bitter', 5, lateLastWeek),
          ...qualifiedPlays('angel', 'album-angel', 10, thisWeek),
          ...qualifiedPlays('fresh', 'album-fresh', 2, thisWeek),
        ]),
      ).load(chartType: ChartType.songs, referenceLocal: reference);

      final byId = {
        for (final entry in chart.entries)
          entry.entity.entityId: chart.statsFor(entry),
      };

      expect(byId['angel']!.streamsThisWeek, 10);
      expect(byId['angel']!.streamsSameTimeLastWeek, 43);
      expect(byId['angel']!.weeklyChangePercent, closeTo(-76.74, 0.01));

      expect(byId['bitter']!.streamsSameTimeLastWeek, 36);
      expect(byId['bitter']!.streamsThisWeek, 0);
      expect(byId['bitter']!.weeklyChangePercent, -100);

      expect(byId['fresh']!.weeklyChangePercent, isNull);
      expect(byId['fresh']!.isNewActivity, isTrue);
    });
  });

  test('weeks in zones count each completed week once', () async {
    final chart = await service(
      plays: FakeQualifiedPlayRepository(history),
    ).load(chartType: ChartType.songs, referenceLocal: reference);

    final angel = chart.statsFor(chart.entries[0]).zones;
    final bitter = chart.statsFor(chart.entries[1]).zones;

    // One completed week (4–10 October); the current week never counts.
    expect(angel.weeksIn(3), 1);
    expect(angel.weeksIn(200), 1);
    expect(bitter.weeksIn(3), 1);
    expect(bitter.bestZone, 3);
  });
}

class _EmptyChartRepository implements ChartRepository {
  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async => const [];

  @override
  Future<ChartSnapshot?> getById(String id) => throw UnimplementedError();

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) =>
      throw UnimplementedError();
}
