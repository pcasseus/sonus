import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/analytics_account_attachment_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  final startedAt = DateTime.utc(2026, 9, 26, 12);

  PlaybackSession session({required String id, String? userId}) {
    return PlaybackSession(
      id: id,
      userId: userId,
      songId: 'song_$id',
      artistId: 'artist_$id',
      albumId: 'album_$id',
      albumEditionId: 'edition_$id',
      songTitle: 'Song $id',
      artistName: 'Artist $id',
      albumTitle: 'Album $id',
      albumEditionTitle: 'Album $id',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 1)),
      listenedDuration: const Duration(seconds: 45),
      trackDuration: const Duration(minutes: 3),
      finalPosition: const Duration(seconds: 45),
      endReason: PlaybackSessionEndReason.skipped,
      sourceContext: 'library',
      createdAt: startedAt,
      updatedAt: startedAt.add(const Duration(minutes: 1)),
    );
  }

  QualifiedPlay play({
    required String id,
    required PlaybackSession session,
    String? userId,
  }) {
    return QualifiedPlay(
      id: id,
      playbackSessionId: session.id,
      userId: userId,
      songId: session.songId,
      artistId: session.artistId,
      albumId: session.albumId,
      albumEditionId: session.albumEditionId,
      qualifiedAt: startedAt.add(const Duration(seconds: 30)),
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 3),
      createdAt: startedAt.add(const Duration(seconds: 30)),
    );
  }

  test('attaches only anonymous sessions and their qualified plays', () async {
    final anonymous = session(id: 'anonymous');
    final alreadyOwned = session(id: 'owned', userId: 'other-user');

    final anonymousPlay = play(id: 'play_anonymous', session: anonymous);

    final ownedPlay = play(
      id: 'play_owned',
      session: alreadyOwned,
      userId: 'other-user',
    );

    final playbackSessions = _MemoryPlaybackSessionRepository([
      anonymous,
      alreadyOwned,
    ]);

    final qualifiedPlays = _MemoryQualifiedPlayRepository([
      anonymousPlay,
      ownedPlay,
    ]);

    final service = AnalyticsAccountAttachmentService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    final result = await service.attachUnownedToUser(' user-1 ');

    expect(result.sessionsAttached, 1);
    expect(result.qualifiedPlaysAttached, 1);

    final attachedSession = await playbackSessions.getById(anonymous.id);
    final untouchedSession = await playbackSessions.getById(alreadyOwned.id);

    expect(attachedSession!.userId, 'user-1');
    expect(attachedSession.id, anonymous.id);
    expect(attachedSession.startedAt, anonymous.startedAt);
    expect(attachedSession.createdAt, anonymous.createdAt);
    expect(attachedSession.updatedAt, anonymous.updatedAt);

    expect(untouchedSession!.userId, 'other-user');

    final attachedPlay = await qualifiedPlays.getById(anonymousPlay.id);
    final untouchedPlay = await qualifiedPlays.getById(ownedPlay.id);

    expect(attachedPlay!.userId, 'user-1');
    expect(attachedPlay.id, anonymousPlay.id);
    expect(attachedPlay.playbackSessionId, anonymousPlay.playbackSessionId);
    expect(attachedPlay.qualifiedAt, anonymousPlay.qualifiedAt);
    expect(attachedPlay.createdAt, anonymousPlay.createdAt);

    expect(untouchedPlay!.userId, 'other-user');
  });

  test('attachment is idempotent', () async {
    final anonymous = session(id: 'anonymous');
    final anonymousPlay = play(id: 'play_anonymous', session: anonymous);

    final playbackSessions = _MemoryPlaybackSessionRepository([anonymous]);
    final qualifiedPlays = _MemoryQualifiedPlayRepository([anonymousPlay]);

    final service = AnalyticsAccountAttachmentService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    final first = await service.attachUnownedToUser('user-1');
    final second = await service.attachUnownedToUser('user-1');

    expect(first.sessionsAttached, 1);
    expect(first.qualifiedPlaysAttached, 1);

    expect(second.sessionsAttached, 0);
    expect(second.qualifiedPlaysAttached, 0);

    expect(playbackSessions.saveCallCount, 1);
    expect(qualifiedPlays.saveCallCount, 1);
  });

  test('rejects conflicting qualified-play ownership before writes', () async {
    final anonymous = session(id: 'anonymous');

    final conflictingPlay = play(
      id: 'play_conflict',
      session: anonymous,
      userId: 'different-user',
    );

    final playbackSessions = _MemoryPlaybackSessionRepository([anonymous]);
    final qualifiedPlays = _MemoryQualifiedPlayRepository([conflictingPlay]);

    final service = AnalyticsAccountAttachmentService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    await expectLater(
      service.attachUnownedToUser('user-1'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Qualified play play_conflict belongs to a different user.',
        ),
      ),
    );

    expect(playbackSessions.saveCallCount, 0);
    expect(qualifiedPlays.saveCallCount, 0);

    expect((await playbackSessions.getById(anonymous.id))!.userId, isNull);
  });

  test('accepts a play already owned by the target user', () async {
    final anonymous = session(id: 'anonymous');

    final ownedPlay = play(
      id: 'play_owned',
      session: anonymous,
      userId: 'user-1',
    );

    final playbackSessions = _MemoryPlaybackSessionRepository([anonymous]);
    final qualifiedPlays = _MemoryQualifiedPlayRepository([ownedPlay]);

    final service = AnalyticsAccountAttachmentService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    final result = await service.attachUnownedToUser('user-1');

    expect(result.sessionsAttached, 1);
    expect(result.qualifiedPlaysAttached, 0);

    expect((await playbackSessions.getById(anonymous.id))!.userId, 'user-1');

    expect(qualifiedPlays.saveCallCount, 0);
  });

  test('rejects a blank user id without writes', () async {
    final anonymous = session(id: 'anonymous');

    final playbackSessions = _MemoryPlaybackSessionRepository([anonymous]);
    final qualifiedPlays = _MemoryQualifiedPlayRepository();

    final service = AnalyticsAccountAttachmentService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    await expectLater(
      () => service.attachUnownedToUser('   '),
      throwsA(isA<ArgumentError>()),
    );

    expect(playbackSessions.saveCallCount, 0);
    expect(qualifiedPlays.saveCallCount, 0);
  });
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  _MemoryPlaybackSessionRepository([
    Iterable<PlaybackSession> sessions = const [],
  ]) {
    for (final session in sessions) {
      _values[session.id] = session;
    }
  }

  final Map<String, PlaybackSession> _values = {};

  int saveCallCount = 0;

  @override
  Future<void> create(PlaybackSession session) async {
    _values[session.id] = session;
  }

  @override
  Future<void> save(PlaybackSession session) async {
    if (!_values.containsKey(session.id)) {
      throw StateError('Playback session not found: ${session.id}');
    }

    saveCallCount++;
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
        .where((value) => !value.isEnded)
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
    return _values.values.take(limit).toList(growable: false);
  }
}

class _MemoryQualifiedPlayRepository implements QualifiedPlayRepository {
  _MemoryQualifiedPlayRepository([Iterable<QualifiedPlay> plays = const []]) {
    for (final play in plays) {
      _values[play.id] = play;
    }
  }

  final Map<String, QualifiedPlay> _values = {};

  int saveCallCount = 0;

  @override
  Future<void> create(QualifiedPlay play) async {
    _values[play.id] = play;
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    if (!_values.containsKey(play.id)) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    saveCallCount++;
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
