// ignore_for_file: prefer_initializing_formals

import '../../domain/models/listening_history_cursor.dart';
import '../models/listening_history_entry.dart';
import '../models/listening_history_page.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';

class ListeningHistoryService {
  const ListeningHistoryService({
    required PlaybackSessionRepository playbackSessions,
    required QualifiedPlayRepository qualifiedPlays,
  }) : _playbackSessions = playbackSessions,
       _qualifiedPlays = qualifiedPlays;

  final PlaybackSessionRepository _playbackSessions;
  final QualifiedPlayRepository _qualifiedPlays;

  Future<ListeningHistoryPage> getPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    int limit = 50,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
    }

    final sessions = await _playbackSessions.getHistoryPage(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
      before: before,
      limit: limit + 1,
    );

    final hasMore = sessions.length > limit;

    final pageSessions = hasMore
        ? sessions.take(limit).toList(growable: false)
        : sessions;

    final plays = await _qualifiedPlays.getByPlaybackSessionIds(
      pageSessions.map((session) => session.id),
    );

    final playBySessionId = {
      for (final play in plays) play.playbackSessionId: play,
    };

    final entries = pageSessions
        .map(
          (session) => ListeningHistoryEntry(
            session: session,
            qualifiedPlay: playBySessionId[session.id],
          ),
        )
        .toList(growable: false);

    final nextCursor = hasMore && pageSessions.isNotEmpty
        ? ListeningHistoryCursor(
            startedAt: pageSessions.last.startedAt,
            sessionId: pageSessions.last.id,
          )
        : null;

    return ListeningHistoryPage(
      entries: entries,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }
}
