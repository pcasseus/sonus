// SN-50 F-Q25: the feed reads bounded pages, and only ever whole days.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_pager.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';

import '../../support/moment_page_fakes.dart';

void main() {
  // Three on the 12th, three on the 11th, two on the 10th (local days).
  final stored = [
    for (final (day, count) in [(12, 3), (11, 3), (10, 2)])
      for (var i = 0; i < count; i++)
        _event('d$day-$i', DateTime(2026, 10, day, 9 + i)),
  ];

  test(
    'a page that ends inside a day reads on until the day is whole',
    () async {
      final repository = _Repository(stored);
      final pager = ChartMomentFeedPager(repository, pageSize: 2);

      await pager.loadMore();

      expect(pager.events.map((event) => event.id), [
        'd12-2',
        'd12-1',
        'd12-0',
        'd11-2',
        'd11-1',
        'd11-0',
      ]);
      expect(
        pager.oldestDay,
        ChartMomentFeedPager.localDay(stored[3].occurredAt),
      );
      expect(pager.hasMore, isTrue);
      expect(repository.reads, lessThan(stored.length));
    },
  );

  test('reading on reaches every Moment once, newest first', () async {
    final pager = ChartMomentFeedPager(_Repository(stored), pageSize: 2);

    while (pager.hasMore) {
      await pager.loadMore();
    }

    expect(
      pager.events.map((event) => event.id),
      momentPageOf(stored, limit: stored.length).map((event) => event.id),
    );
  });

  test('nothing stored: one read, nothing more to load', () async {
    final repository = _Repository(const []);
    final pager = ChartMomentFeedPager(repository, pageSize: 2);

    await pager.loadMore();

    expect(pager.events, isEmpty);
    expect(pager.hasMore, isFalse);
    expect(repository.reads, 1);
  });
}

ChartMomentEvent _event(String id, DateTime local) {
  final week = DateTime.utc(2026, 10, 4);
  return ChartMomentEvent(
    id: id,
    deduplicationKey: id,
    sourceId: 'play-$id',
    chartType: ChartType.songs,
    scope: ChartMomentScope.allTime,
    eventType: ChartMomentEventType.debut,
    entity: ChartEntitySnapshot(
      entityId: 'song-$id',
      title: 'Song $id',
      artistName: 'Ada Lune',
    ),
    weekStartUtc: week,
    weekEndUtc: week.add(const Duration(days: 7)),
    occurredAt: local.toUtc(),
    createdAt: local.toUtc(),
    currentRank: 40,
  );
}

class _Repository implements ChartMomentRepository {
  _Repository(this.events);

  final List<ChartMomentEvent> events;
  int reads = 0;

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async {
    reads++;
    return momentPageOf(events, before: before, limit: limit);
  }

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) =>
      throw UnimplementedError();

  @override
  Future<ChartMomentEvent?> getById(String id) => throw UnimplementedError();

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) =>
      throw UnimplementedError();

  @override
  Future<bool> publishFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) => throw UnimplementedError();
}
