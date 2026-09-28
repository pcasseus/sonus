import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/listening_history_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/listening_history_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/listening_history_page.dart';

void main() {
  testWidgets('shows initializing state without analytics repositories', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ListeningHistoryPage()));

    expect(
      find.byKey(const ValueKey<String>('listening-history-initializing')),
      findsOneWidget,
    );
  });

  testWidgets('shows empty history state', (tester) async {
    final controller = _controller();

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ListeningHistoryPage(controller: controller)),
    );

    expect(
      find.byKey(const ValueKey<String>('listening-history-empty')),
      findsOneWidget,
    );

    expect(find.text('No listening history yet.'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows immutable history metadata', (tester) async {
    final playbackSessions = _MemoryPlaybackSessionRepository();

    playbackSessions.seed(
      _session(
        id: 'session_1',
        songTitle: 'Historical Song',
        artistName: 'Historical Artist',
        albumTitle: 'Historical Album',
        albumEditionTitle: 'Deluxe',
        startedAt: DateTime.utc(2026, 9, 25, 12),
      ),
    );

    final controller = _controller(playbackSessions: playbackSessions);

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ListeningHistoryPage(controller: controller)),
    );

    expect(find.text('Historical Song'), findsOneWidget);
    expect(find.text('Historical Artist'), findsOneWidget);
    expect(find.text('Historical Album • Deluxe'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('listening-history-entry-session_1')),
      findsOneWidget,
    );

    controller.dispose();
  });

  testWidgets('shows qualified and non-qualified sessions', (tester) async {
    final playbackSessions = _MemoryPlaybackSessionRepository();
    final qualifiedPlays = _MemoryQualifiedPlayRepository();

    final qualifiedSession = _session(
      id: 'qualified',
      songTitle: 'Qualified Song',
      startedAt: DateTime.utc(2026, 9, 25, 12),
    );

    final skippedSession = _session(
      id: 'not_qualified',
      songTitle: 'Skipped Song',
      startedAt: DateTime.utc(2026, 9, 25, 11),
    );

    playbackSessions.seed(qualifiedSession);
    playbackSessions.seed(skippedSession);

    qualifiedPlays.seed(
      QualifiedPlay(
        id: 'play_1',
        playbackSessionId: qualifiedSession.id,
        songId: qualifiedSession.songId,
        artistId: qualifiedSession.artistId,
        albumId: qualifiedSession.albumId,
        albumEditionId: qualifiedSession.albumEditionId,
        qualifiedAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
        listenedDuration: const Duration(seconds: 30),
        trackDuration: qualifiedSession.trackDuration,
        createdAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
      ),
    );

    final controller = _controller(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ListeningHistoryPage(controller: controller)),
    );

    expect(find.text('Qualified Song'), findsOneWidget);
    expect(find.text('Skipped Song'), findsOneWidget);
    expect(find.text('Qualified'), findsOneWidget);
    expect(find.text('Not qualified'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows load more control when another page exists', (
    tester,
  ) async {
    final playbackSessions = _MemoryPlaybackSessionRepository();

    playbackSessions.seed(
      _session(
        id: 'session_1',
        songTitle: 'Song 1',
        startedAt: DateTime.utc(2026, 9, 25, 10),
      ),
    );

    playbackSessions.seed(
      _session(
        id: 'session_2',
        songTitle: 'Song 2',
        startedAt: DateTime.utc(2026, 9, 25, 11),
      ),
    );

    playbackSessions.seed(
      _session(
        id: 'session_3',
        songTitle: 'Song 3',
        startedAt: DateTime.utc(2026, 9, 25, 12),
      ),
    );

    final controller = _controller(
      playbackSessions: playbackSessions,
      pageSize: 2,
    );

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: ListeningHistoryPage(controller: controller)),
    );

    expect(find.text('Song 3'), findsOneWidget);
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);

    expect(
      find.byKey(const ValueKey<String>('listening-history-load-more')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('listening-history-load-more')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Song 1'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows clear filter action when a date filter is active', (
    tester,
  ) async {
    final controller = _controller();

    await controller.setDateRange(
      startedAtOrAfter: DateTime.utc(2026, 9, 1),
      startedBefore: DateTime.utc(2026, 10, 1),
    );

    await tester.pumpWidget(
      MaterialApp(home: ListeningHistoryPage(controller: controller)),
    );

    expect(
      find.byKey(const ValueKey<String>('listening-history-clear-filter')),
      findsOneWidget,
    );

    controller.dispose();
  });
}

ListeningHistoryController _controller({
  _MemoryPlaybackSessionRepository? playbackSessions,
  _MemoryQualifiedPlayRepository? qualifiedPlays,
  int pageSize = 50,
}) {
  return ListeningHistoryController(
    service: ListeningHistoryService(
      playbackSessions: playbackSessions ?? _MemoryPlaybackSessionRepository(),
      qualifiedPlays: qualifiedPlays ?? _MemoryQualifiedPlayRepository(),
    ),
    pageSize: pageSize,
  );
}

PlaybackSession _session({
  required String id,
  required String songTitle,
  String artistName = 'Artist',
  String albumTitle = 'Album',
  String albumEditionTitle = 'Standard',
  required DateTime startedAt,
}) {
  return PlaybackSession(
    id: id,
    songId: 'song_$id',
    artistId: 'artist_$id',
    albumId: 'album_$id',
    albumEditionId: 'edition_$id',
    songTitle: songTitle,
    artistName: artistName,
    albumTitle: albumTitle,
    albumEditionTitle: albumEditionTitle,
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
