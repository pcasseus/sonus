import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/application/services/listening_history_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  late _MemoryPlaybackSessionRepository playbackSessions;
  late _MemoryQualifiedPlayRepository qualifiedPlays;
  late ListeningHistoryService service;

  setUp(() {
    playbackSessions = _MemoryPlaybackSessionRepository();
    qualifiedPlays = _MemoryQualifiedPlayRepository();

    service = ListeningHistoryService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );
  });

  test('returns qualified and non-qualified sessions together', () async {
    final qualifiedSession = _session(
      id: 'session_qualified',
      startedAt: DateTime.utc(2026, 9, 25, 12),
    );

    final skippedSession = _session(
      id: 'session_skipped',
      startedAt: DateTime.utc(2026, 9, 25, 11),
    );

    playbackSessions.seed(qualifiedSession);
    playbackSessions.seed(skippedSession);

    final qualifiedAt = DateTime.utc(2026, 9, 25, 12, 0, 30);

    qualifiedPlays.seed(
      _play(
        id: 'play_qualified',
        session: qualifiedSession,
        qualifiedAt: qualifiedAt,
      ),
    );

    final page = await service.getPage(limit: 10);

    expect(page.entries.map((entry) => entry.session.id), [
      'session_qualified',
      'session_skipped',
    ]);

    expect(page.entries[0].isQualified, isTrue);
    expect(page.entries[0].qualifiedAt, qualifiedAt);

    expect(page.entries[1].isQualified, isFalse);
    expect(page.entries[1].qualifiedAt, isNull);

    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('returns next cursor when another page exists', () async {
    playbackSessions.seed(
      _session(id: 'session_3', startedAt: DateTime.utc(2026, 9, 25, 12)),
    );

    playbackSessions.seed(
      _session(id: 'session_2', startedAt: DateTime.utc(2026, 9, 25, 11)),
    );

    playbackSessions.seed(
      _session(id: 'session_1', startedAt: DateTime.utc(2026, 9, 25, 10)),
    );

    final page = await service.getPage(limit: 2);

    expect(page.entries.map((entry) => entry.session.id), [
      'session_3',
      'session_2',
    ]);

    expect(page.hasMore, isTrue);
    expect(page.nextCursor, isNotNull);
    expect(page.nextCursor!.sessionId, 'session_2');
    expect(page.nextCursor!.startedAt, DateTime.utc(2026, 9, 25, 11));
  });

  test('cursor loads following page without overlap', () async {
    for (var hour = 10; hour <= 12; hour++) {
      playbackSessions.seed(
        _session(
          id: 'session_$hour',
          startedAt: DateTime.utc(2026, 9, 25, hour),
        ),
      );
    }

    final first = await service.getPage(limit: 2);
    final second = await service.getPage(before: first.nextCursor, limit: 2);

    expect(first.entries.map((entry) => entry.session.id), [
      'session_12',
      'session_11',
    ]);

    expect(second.entries.map((entry) => entry.session.id), ['session_10']);

    expect(second.hasMore, isFalse);
    expect(second.nextCursor, isNull);

    final ids = [
      ...first.entries.map((entry) => entry.session.id),
      ...second.entries.map((entry) => entry.session.id),
    ];

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('passes date boundaries into the session query', () async {
    playbackSessions.seed(
      _session(id: 'outside_before', startedAt: DateTime.utc(2026, 9, 20)),
    );

    playbackSessions.seed(
      _session(id: 'inside', startedAt: DateTime.utc(2026, 9, 25)),
    );

    playbackSessions.seed(
      _session(id: 'outside_end', startedAt: DateTime.utc(2026, 9, 28)),
    );

    final page = await service.getPage(
      startedAtOrAfter: DateTime.utc(2026, 9, 21),
      startedBefore: DateTime.utc(2026, 9, 28),
    );

    expect(page.entries.map((entry) => entry.session.id), ['inside']);
  });

  test('empty history returns an empty final page', () async {
    final page = await service.getPage();

    expect(page.entries, isEmpty);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('rejects non-positive page limits', () async {
    await expectLater(service.getPage(limit: 0), throwsArgumentError);
  });
}

PlaybackSession _session({required String id, required DateTime startedAt}) {
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

QualifiedPlay _play({
  required String id,
  required PlaybackSession session,
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: session.id,
    songId: session.songId,
    artistId: session.artistId,
    albumId: session.albumId,
    albumEditionId: session.albumEditionId,
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: session.trackDuration,
    createdAt: qualifiedAt,
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
