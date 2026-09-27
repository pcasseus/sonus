import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_time_window_resolver.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';

void main() {
  const resolver = AnalyticsTimeWindowResolver();

  late _FakePlaybackListeningSegmentRepository repository;
  late AnalyticsListeningDurationService service;

  final referenceLocal = DateTime(2026, 9, 25, 12);

  late DateTime dayStart;
  late DateTime dayEnd;

  setUp(() {
    repository = _FakePlaybackListeningSegmentRepository();

    service = AnalyticsListeningDurationService(listeningSegments: repository);

    final window = resolver.resolve(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    dayStart = window.startUtc!;
    dayEnd = window.endUtc!;
  });

  test('returns zero when there are no listening segments', () async {
    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, Duration.zero);
    expect(result.hasListening, isFalse);
  });

  test('counts a segment fully inside the period', () async {
    repository.seed(
      _closedSegment(
        id: 'inside',
        startedAt: dayStart.add(const Duration(hours: 4)),
        duration: const Duration(minutes: 30),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, const Duration(minutes: 30));
  });

  test('clips a segment crossing the start boundary', () async {
    repository.seed(
      _closedSegment(
        id: 'cross_start',
        startedAt: dayStart.subtract(const Duration(minutes: 10)),
        duration: const Duration(minutes: 25),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, const Duration(minutes: 15));
  });

  test('clips a segment crossing the end boundary', () async {
    repository.seed(
      _closedSegment(
        id: 'cross_end',
        startedAt: dayEnd.subtract(const Duration(minutes: 8)),
        duration: const Duration(minutes: 20),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, const Duration(minutes: 8));
  });

  test('segment ending exactly at start boundary counts zero', () async {
    repository.seed(
      _closedSegment(
        id: 'ends_at_start',
        startedAt: dayStart.subtract(const Duration(minutes: 10)),
        duration: const Duration(minutes: 10),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, Duration.zero);
  });

  test('segment starting exactly at exclusive end counts zero', () async {
    repository.seed(
      _closedSegment(
        id: 'starts_at_end',
        startedAt: dayEnd,
        duration: const Duration(minutes: 10),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, Duration.zero);

    expect(repository.lastStartedBefore, dayEnd);
  });

  test('multiple audible segments sum without paused gaps', () async {
    repository.seedAll([
      _closedSegment(
        id: 'first',
        startedAt: dayStart.add(const Duration(hours: 2)),
        duration: const Duration(minutes: 10),
      ),
      _closedSegment(
        id: 'second',
        startedAt: dayStart.add(const Duration(hours: 5)),
        duration: const Duration(minutes: 15),
      ),
    ]);

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, const Duration(minutes: 25));
  });

  test('open segment counts only its persisted listened duration', () async {
    final startedAt = dayStart.add(const Duration(hours: 6));

    repository.seed(
      PlaybackListeningSegment(
        id: 'open_checkpointed',
        playbackSessionId: 'session_open',
        startedAt: startedAt,
        listenedDuration: const Duration(minutes: 7),
        createdAt: startedAt,
        updatedAt: startedAt.add(const Duration(hours: 3)),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, const Duration(minutes: 7));
  });

  test('lifetime sums complete segment durations', () async {
    repository.seedAll([
      _closedSegment(
        id: 'old',
        startedAt: DateTime.utc(2020, 1, 1),
        duration: const Duration(minutes: 40),
      ),
      _closedSegment(
        id: 'new',
        startedAt: DateTime.utc(2026, 9, 25),
        duration: const Duration(minutes: 20),
      ),
    ]);

    final result = await service.load(
      period: AnalyticsPeriod.lifetime,
      referenceLocal: referenceLocal,
    );

    expect(repository.lastStartedBefore, isNull);

    expect(result.totalAudibleListeningDuration, const Duration(hours: 1));
  });

  test('a segment spanning the entire day counts exactly the day', () async {
    repository.seed(
      _closedSegment(
        id: 'whole_window',
        startedAt: dayStart.subtract(const Duration(hours: 3)),
        duration: dayEnd.difference(dayStart) + const Duration(hours: 6),
      ),
    );

    final result = await service.load(
      period: AnalyticsPeriod.day,
      referenceLocal: referenceLocal,
    );

    expect(result.totalAudibleListeningDuration, dayEnd.difference(dayStart));
  });
}

PlaybackListeningSegment _closedSegment({
  required String id,
  required DateTime startedAt,
  required Duration duration,
}) {
  final endedAt = startedAt.add(duration);

  return PlaybackListeningSegment(
    id: id,
    playbackSessionId: 'session_$id',
    startedAt: startedAt,
    endedAt: endedAt,
    listenedDuration: duration,
    createdAt: startedAt,
    updatedAt: endedAt,
  );
}

class _FakePlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  final List<PlaybackListeningSegment> _segments = [];

  DateTime? lastStartedBefore;

  void seed(PlaybackListeningSegment segment) {
    _segments.add(segment);
  }

  void seedAll(Iterable<PlaybackListeningSegment> segments) {
    _segments.addAll(segments);
  }

  @override
  Future<void> create(PlaybackListeningSegment segment) async {
    _segments.add(segment);
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) async {
    final index = _segments.indexWhere((value) => value.id == segment.id);

    if (index < 0) {
      throw StateError('Missing listening segment: ${segment.id}');
    }

    _segments[index] = segment;
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async {
    for (final segment in _segments) {
      if (segment.id == id) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    for (final segment in _segments.reversed) {
      if (segment.playbackSessionId == playbackSessionId && !segment.isEnded) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    return _segments
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    lastStartedBefore = startedBefore;

    return _segments
        .where((segment) {
          if (startedBefore != null &&
              !segment.startedAt.toUtc().isBefore(startedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }
}
