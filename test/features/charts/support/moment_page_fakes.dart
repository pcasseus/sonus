import 'package:sonus_next/features/charts/application/services/moments_last_seen_store.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';

/// [ChartMomentRepository.getPage] over events in memory: newest first by
/// occurred time then id, like the stored index.
List<ChartMomentEvent> momentPageOf(
  Iterable<ChartMomentEvent> events, {
  ChartMomentPageCursor? before,
  required int limit,
}) {
  int compare(DateTime occurredAt, String id, ChartMomentEvent event) {
    final byTime = occurredAt.compareTo(event.occurredAt);
    return byTime != 0 ? byTime : id.compareTo(event.id);
  }

  final ordered = events.toList()
    ..sort((a, b) => compare(b.occurredAt, b.id, a));

  return List.unmodifiable(
    ordered
        .where(
          (event) =>
              before == null ||
              compare(before.occurredAt, before.id, event) > 0,
        )
        .take(limit),
  );
}

/// Keeps the Moments last-seen time in memory.
class MemoryMomentsLastSeenStore implements MomentsLastSeenStore {
  MemoryMomentsLastSeenStore([this.seen]);

  DateTime? seen;
  int writes = 0;

  @override
  Future<DateTime?> read() async => seen;

  @override
  Future<void> write(DateTime newestSeenUtc) async {
    writes++;
    seen = newestSeenUtc;
  }
}
