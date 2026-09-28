import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/listening_history_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/listening_history_controller.dart';

void main() {
  late _MemoryPlaybackSessionRepository playbackSessions;
  late _MemoryQualifiedPlayRepository qualifiedPlays;
  late ListeningHistoryController controller;

  setUp(() {
    playbackSessions = _MemoryPlaybackSessionRepository();
    qualifiedPlays = _MemoryQualifiedPlayRepository();

    controller = ListeningHistoryController(
      service: ListeningHistoryService(
        playbackSessions: playbackSessions,
        qualifiedPlays: qualifiedPlays,
      ),
      pageSize: 2,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('load populates first page newest first', () async {
    playbackSessions.seed(_session('session_1', 10));
    playbackSessions.seed(_session('session_2', 11));
    playbackSessions.seed(_session('session_3', 12));

    await controller.load();

    expect(controller.entries.map((entry) => entry.session.id), [
      'session_3',
      'session_2',
    ]);

    expect(controller.hasMore, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);
  });

  test('loadMore appends the next page', () async {
    playbackSessions.seed(_session('session_1', 10));
    playbackSessions.seed(_session('session_2', 11));
    playbackSessions.seed(_session('session_3', 12));

    await controller.load();
    await controller.loadMore();

    expect(controller.entries.map((entry) => entry.session.id), [
      'session_3',
      'session_2',
      'session_1',
    ]);

    expect(controller.hasMore, isFalse);
  });

  test('qualified state is preserved in controller entries', () async {
    final session = _session('session_qualified', 12);

    playbackSessions.seed(session);

    qualifiedPlays.seed(
      QualifiedPlay(
        id: 'play_1',
        playbackSessionId: session.id,
        songId: session.songId,
        artistId: session.artistId,
        albumId: session.albumId,
        albumEditionId: session.albumEditionId,
        qualifiedAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
        listenedDuration: const Duration(seconds: 30),
        trackDuration: session.trackDuration,
        createdAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
      ),
    );

    await controller.load();

    expect(controller.entries.single.isQualified, isTrue);
    expect(
      controller.entries.single.qualifiedAt,
      DateTime.utc(2026, 9, 25, 12, 0, 30),
    );
  });

  test('date range reloads history using half-open boundaries', () async {
    playbackSessions.seed(_session('before', 8));
    playbackSessions.seed(_session('inside', 12));
    playbackSessions.seed(_session('end', 16));

    await controller.setDateRange(
      startedAtOrAfter: DateTime.utc(2026, 9, 25, 10),
      startedBefore: DateTime.utc(2026, 9, 25, 16),
    );

    expect(controller.entries.map((entry) => entry.session.id), ['inside']);

    expect(controller.hasDateFilter, isTrue);
  });

  test('clearDateRange restores unfiltered history', () async {
    playbackSessions.seed(_session('morning', 8));
    playbackSessions.seed(_session('afternoon', 14));

    await controller.setDateRange(
      startedAtOrAfter: DateTime.utc(2026, 9, 25, 12),
    );

    expect(controller.entries.map((entry) => entry.session.id), ['afternoon']);

    await controller.clearDateRange();

    expect(controller.entries.map((entry) => entry.session.id), [
      'afternoon',
      'morning',
    ]);

    expect(controller.hasDateFilter, isFalse);
  });

  test('rejects an invalid date range', () async {
    await expectLater(
      controller.setDateRange(
        startedAtOrAfter: DateTime.utc(2026, 9, 25, 12),
        startedBefore: DateTime.utc(2026, 9, 25, 12),
      ),
      throwsArgumentError,
    );
  });

  test('reports empty history', () async {
    await controller.load();

    expect(controller.entries, isEmpty);
    expect(controller.isEmpty, isTrue);
    expect(controller.hasMore, isFalse);
  });

  test('rejects a non-positive page size', () {
    expect(
      () => ListeningHistoryController(
        service: ListeningHistoryService(
          playbackSessions: playbackSessions,
          qualifiedPlays: qualifiedPlays,
        ),
        pageSize: 0,
      ),
      throwsArgumentError,
    );
  });
}

PlaybackSession _session(String id, int hour) {
  final startedAt = DateTime.utc(2026, 9, 25, hour);

  return PlaybackSession(
    id: id,
    songId: 'song_$id',
    artistId: 'artist_$id',
    albumId: 'album_$id',
    albumEditionId: 'edition_$id',
    songTitle: 'Song $id',
    artistName: 'Artist $id',
    albumTitle: 'Album $id',
    albumEditionTitle: 'Edition $id',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 2)),
    listenedDuration: const Duration(seconds: 20),
    trackDuration: const Duration(minutes: 3),
    finalPosition: const Duration(seconds: 20),
    endReason: PlaybackSessionEndReason.skipped,
    sourceContext: 'library',
    createdAt: startedAt,
    updatedAt: startedAt.add(const Duration(minutes: 2)),
  );
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  final Map<String, PlaybackSession> _values = {};

  void seed(PlaybackSession session) {
    _values[session.id] = session;
  }

  @override
  Future<void> create(PlaybackSession session) async {
    _values[session.id] = session;
  }

  @override
  Future<void> save(PlaybackSession session) async {
    _values[session.id] = session;
  }

  @override
  Future<PlaybackSession?> getById(String id) async => _values[id];

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _values.values
        .where((session) => !session.isEnded)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return _values.values.toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final result =
        _values.values.where((session) {
          final startedAt = session.startedAt.toUtc();

          if (startedAtOrAfter != null &&
              startedAt.isBefore(startedAtOrAfter.toUtc())) {
            return false;
          }

          if (startedBefore != null &&
              !startedAt.isBefore(startedBefore.toUtc())) {
            return false;
          }

          if (before != null) {
            final cursorStartedAt = before.startedAt.toUtc();

            if (startedAt.isAfter(cursorStartedAt)) {
              return false;
            }

            if (startedAt == cursorStartedAt &&
                session.id.compareTo(before.sessionId) >= 0) {
              return false;
            }
          }

          return true;
        }).toList()..sort((a, b) {
          final byStartedAt = b.startedAt.compareTo(a.startedAt);

          if (byStartedAt != 0) {
            return byStartedAt;
          }

          return b.id.compareTo(a.id);
        });

    return result.take(limit).toList(growable: false);
  }
}

class _MemoryQualifiedPlayRepository implements QualifiedPlayRepository {
  final Map<String, QualifiedPlay> _values = {};

  void seed(QualifiedPlay play) {
    _values[play.id] = play;
  }

  @override
  Future<void> create(QualifiedPlay play) async {
    _values[play.id] = play;
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    if (!_values.containsKey(play.id)) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    _values[play.id] = play;
  }

  @override
  Future<QualifiedPlay?> getById(String id) async => _values[id];

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    for (final play in _values.values) {
      if (play.playbackSessionId == playbackSessionId) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final ids = playbackSessionIds.toSet();

    return _values.values
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return _values.values.toList(growable: false);
  }
}
