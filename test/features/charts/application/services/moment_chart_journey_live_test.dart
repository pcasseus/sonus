import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/moment_chart_journey_service.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';

/// App Update 1.3 (REF-1.3-02): the Chart Journey's live position is the
/// rank now, from the same replay as the completed days; it is never a day
/// of its own and the journey never writes anything.
class _ReadOnlyPlays implements QualifiedPlayRepository {
  _ReadOnlyPlays(this.plays);

  final List<QualifiedPlay> plays;
  int reads = 0;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    reads++;
    return List.unmodifiable(plays);
  }

  @override
  Future<void> create(QualifiedPlay play) =>
      throw StateError('the journey must never write plays');

  @override
  Future<void> save(QualifiedPlay play) =>
      throw StateError('the journey must never write plays');

  @override
  Future<QualifiedPlay?> getById(String id) => throw UnimplementedError();

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(String id) =>
      throw UnimplementedError();

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(Iterable<String> ids) =>
      throw UnimplementedError();
}

QualifiedPlay _play(String id, String song, DateTime local) => QualifiedPlay(
  id: id,
  playbackSessionId: 'session-$id',
  songId: song,
  artistId: 'artist',
  albumId: 'album-$song',
  albumEditionId: 'edition-$song',
  qualifiedAt: local.toUtc(),
  listenedDuration: const Duration(minutes: 3),
  trackDuration: const Duration(minutes: 3),
  createdAt: local.toUtc(),
);

void main() {
  // Nov 3: A twice, B once (A #1 at the close). Today, Nov 4: B three
  // times by 10:00, so B leads now and A is #2, provisionally.
  final plays = [
    _play('a1', 'A', DateTime(2026, 11, 3, 9)),
    _play('a2', 'A', DateTime(2026, 11, 3, 10)),
    _play('b1', 'B', DateTime(2026, 11, 3, 11)),
    _play('b2', 'B', DateTime(2026, 11, 4, 8)),
    _play('b3', 'B', DateTime(2026, 11, 4, 9)),
    _play('b4', 'B', DateTime(2026, 11, 4, 10)),
  ];

  MomentChartJourneyService service(_ReadOnlyPlays repository) =>
      MomentChartJourneyService(
        qualifiedPlays: repository,
        now: () => DateTime(2026, 11, 4, 15),
      );

  test('the live rank is the rank now; completed days stay as they '
      'closed', () async {
    final repository = _ReadOnlyPlays(plays);
    final journey = await service(
      repository,
    ).load(chartType: ChartType.songs, entityId: 'A');

    expect(journey, isNotNull);
    expect(journey!.currentRank, 2, reason: 'B overtook A today');
    expect(
      [for (final day in journey.days) (day.dayStartLocal, day.rank)],
      [(DateTime(2026, 11, 3), 1)],
      reason: 'today is not a completed day: no live point is stored',
    );
    expect(repository.reads, 1);
  });

  test('loading again reads again and changes nothing', () async {
    final repository = _ReadOnlyPlays(plays);
    final first = await service(
      repository,
    ).load(chartType: ChartType.songs, entityId: 'A');
    final second = await service(
      repository,
    ).load(chartType: ChartType.songs, entityId: 'A');

    expect(repository.plays, hasLength(6));
    expect(second!.currentRank, first!.currentRank);
    expect(second.days.single.rank, first.days.single.rank);
  });

  test('a song never played has no journey and no live rank', () async {
    final journey = await service(
      _ReadOnlyPlays(plays),
    ).load(chartType: ChartType.songs, entityId: 'never-played');
    expect(journey, isNull);
  });
}
