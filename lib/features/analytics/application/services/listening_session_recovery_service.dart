// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/entities/playback_session.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';

class ListeningSessionRecoveryService {
  const ListeningSessionRecoveryService({
    required PlaybackSessionRepository playbackSessions,
    required PlaybackListeningSegmentRepository listeningSegments,
  }) : _playbackSessions = playbackSessions,
       _listeningSegments = listeningSegments;

  final PlaybackSessionRepository _playbackSessions;
  final PlaybackListeningSegmentRepository _listeningSegments;

  Future<int> recoverInterruptedSessions() async {
    final openSessions = await _playbackSessions.getOpen();

    for (final session in openSessions) {
      final openSegment = await _listeningSegments.getOpenForSession(
        session.id,
      );

      if (openSegment != null) {
        final segmentEndedAt = _safeSegmentEndpoint(openSegment);

        await _listeningSegments.save(
          openSegment.copyWith(
            endedAt: segmentEndedAt,
            updatedAt: segmentEndedAt,
          ),
        );
      }

      final segments = await _listeningSegments.getForSession(session.id);

      final recoveredListeningDuration = segments.fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.listenedDuration,
      );

      final endedAt = segments.isEmpty
          ? _safeSessionEndpoint(session)
          : _latestSegmentEndpoint(segments);

      await _playbackSessions.save(
        session.copyWith(
          endedAt: endedAt,
          listenedDuration: recoveredListeningDuration,
          endReason: PlaybackSessionEndReason.interrupted,
          updatedAt: endedAt,
        ),
      );
    }

    return openSessions.length;
  }

  DateTime _safeSessionEndpoint(PlaybackSession session) {
    return session.updatedAt.isBefore(session.startedAt)
        ? session.startedAt
        : session.updatedAt;
  }

  DateTime _latestSegmentEndpoint(List<PlaybackListeningSegment> segments) {
    var latest = _safeSegmentEndpoint(segments.first);

    for (final segment in segments.skip(1)) {
      final endpoint = _safeSegmentEndpoint(segment);

      if (endpoint.isAfter(latest)) {
        latest = endpoint;
      }
    }

    return latest;
  }

  DateTime _safeSegmentEndpoint(PlaybackListeningSegment segment) {
    final endpoint =
        segment.endedAt ?? segment.startedAt.add(segment.listenedDuration);

    return endpoint.isBefore(segment.startedAt) ? segment.startedAt : endpoint;
  }
}
