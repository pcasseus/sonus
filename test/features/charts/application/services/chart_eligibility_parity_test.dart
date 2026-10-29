import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/application/services/this_week_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';

import '../../support/all_time_chart_fakes.dart';

/// SN-50 R1: Career standings, This Week and a newly finalized week agree
/// on who charts. Only a blocked song is left out; a song whose file is
/// missing, or that this device's library does not hold, keeps its
/// verified listening.
void main() {
  final reference = DateTime(2026, 10, 15, 9);
  final week = const ChartWeekResolver().resolve(reference);

  final plays = <QualifiedPlay>[
    ...qualifiedPlays('available', 'album-available', 4, week.startUtc),
    ...qualifiedPlays('missing-file', 'album-available', 3, week.startUtc),
    ...qualifiedPlays('not-imported', 'album-not-imported', 2, week.startUtc),
    ...qualifiedPlays('blocked', 'album-blocked', 5, week.startUtc),
  ];
  final library = FakeChartLibrary(
    tracks: [
      libraryTrack('available', 'album-available'),
      libraryTrack('missing-file', 'album-available', available: false),
      libraryTrack('blocked', 'album-blocked', blocked: true),
    ],
    albums: [libraryAlbum('album-available'), libraryAlbum('album-blocked')],
  );
  final sessions = FakePlaybackSessions(plays);

  ChartSnapshotBuilderService builder() => ChartSnapshotBuilderService(
    qualifiedPlays: FakeQualifiedPlayRepository(plays),
    library: library,
    charts: _NoHistory(),
    playbackSessions: sessions,
  );

  Future<Map<String, List<ChartEntry>>> everyView(ChartType type) async {
    final career = await AllTimeChartService(
      qualifiedPlays: FakeQualifiedPlayRepository(plays),
      library: library,
      playbackSessions: sessions,
    ).load(chartType: type, referenceLocal: reference);
    final thisWeek = await ThisWeekChartService(
      builder: builder(),
    ).load(chartType: type, referenceLocal: reference);
    final finalized = await builder().build(
      chartType: type,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      finalizedAt: week.endUtc,
    );

    return {
      'career': career.entries,
      'this week': thisWeek.snapshot.entries,
      'finalized': finalized.entries,
    };
  }

  test('songs: only the blocked song is left out, in every view', () async {
    final views = await everyView(ChartType.songs);

    for (final MapEntry(key: view, value: entries) in views.entries) {
      expect(entries.map((entry) => entry.entity.entityId), [
        'available',
        'missing-file',
        'not-imported',
      ], reason: view);
      expect(entries.map((entry) => entry.qualifiedStreamCount), [
        4,
        3,
        2,
      ], reason: view);
      expect(
        entries.last.entity.title,
        'Heard not-imported',
        reason: '$view shows a song this library lacks as it was heard',
      );
    }
  });

  test('releases: one this library lacks still charts, in every '
      'view', () async {
    final views = await everyView(ChartType.albums);

    for (final MapEntry(key: view, value: entries) in views.entries) {
      expect(entries.map((entry) => entry.entity.entityId).toSet(), {
        'album-available',
        'album-blocked',
        'album-not-imported',
      }, reason: view);
      expect(
        entries
            .firstWhere(
              (entry) => entry.entity.entityId == 'album-not-imported',
            )
            .entity
            .title,
        'Heard album-not-imported',
        reason: view,
      );
    }
  });
}

class _NoHistory implements ChartRepository {
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
