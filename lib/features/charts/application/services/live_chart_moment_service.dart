// ignore_for_file: prefer_initializing_formals

import '../../../library/application/repositories/library_query_repository.dart';
import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_live_detector.dart';
import '../../domain/moments/chart_moment_rank_observation.dart';
import '../../domain/repositories/chart_moment_repository.dart';
import '../../domain/services/chart_week_resolver.dart';
import '../models/live_chart_moment_result.dart';
import 'chart_snapshot_builder_service.dart';

class LiveChartMomentService {
  const LiveChartMomentService({
    required ChartSnapshotBuilderService builder,
    required LibraryQueryRepository library,
    required ChartMomentRepository moments,
    ChartWeekResolver weekResolver = const ChartWeekResolver(),
    ChartMomentLiveDetector detector = const ChartMomentLiveDetector(),
  }) : _builder = builder,
       _library = library,
       _moments = moments,
       _weekResolver = weekResolver,
       _detector = detector;

  final ChartSnapshotBuilderService _builder;
  final LibraryQueryRepository _library;
  final ChartMomentRepository _moments;
  final ChartWeekResolver _weekResolver;
  final ChartMomentLiveDetector _detector;

  Future<LiveChartMomentResult> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    String? userId,
  }) async {
    final week = _weekResolver.resolve(referenceLocal);
    final observations = <ChartMomentRankObservation>[];

    final snapshot = await _builder.build(
      chartType: chartType,
      weekStartUtc: week.startUtc,
      weekEndUtc: week.endUtc,
      onRankObservation: observations.add,
    );

    final entities = await _entitySnapshots(chartType);
    final createdAt = DateTime.now().toUtc();

    final moments = <ChartMomentEvent>[];

    for (final observation in observations) {
      final entity = entities[observation.entityId];

      if (entity == null) {
        continue;
      }
      final detected = _detector.detectRankTransition(
        chartType: chartType,
        entity: entity,
        weekStartUtc: week.startUtc,
        weekEndUtc: week.endUtc,
        observation: observation,
        createdAt: createdAt,
        userId: userId,
      );

      moments.addAll(detected);
    }

    await _moments.saveAll(moments);

    return LiveChartMomentResult(
      snapshot: snapshot,
      moments: List.unmodifiable(moments),
    );
  }

  Future<Map<String, ChartEntitySnapshot>> _entitySnapshots(
    ChartType chartType,
  ) async {
    switch (chartType) {
      case ChartType.songs:
        final tracks = await _library.getTracks();

        return {
          for (final track in tracks)
            if (!track.isBlocked)
              track.songId: ChartEntitySnapshot(
                entityId: track.songId,
                title: track.title,
                artistId: track.artistId,
                artistName: track.artistName,
                albumTitle: track.albumTitle,
              ),
        };

      case ChartType.albums:
        final albums = await _library.getAlbums();

        return {
          for (final album in albums)
            album.albumId: ChartEntitySnapshot(
              entityId: album.albumId,
              title: album.title,
              artistId: album.artistId,
              artistName: album.artistName,
            ),
        };
    }
  }
}
