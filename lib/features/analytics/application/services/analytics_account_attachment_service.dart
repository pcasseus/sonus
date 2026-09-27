import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';

class AnalyticsAccountAttachmentResult {
  const AnalyticsAccountAttachmentResult({
    required this.sessionsAttached,
    required this.qualifiedPlaysAttached,
  });

  final int sessionsAttached;
  final int qualifiedPlaysAttached;
}

class AnalyticsAccountAttachmentService {
  const AnalyticsAccountAttachmentService({
    required this._playbackSessions,
    required this._qualifiedPlays,
  });

  final PlaybackSessionRepository _playbackSessions;
  final QualifiedPlayRepository _qualifiedPlays;

  Future<AnalyticsAccountAttachmentResult> attachUnownedToUser(
    String userId,
  ) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    final sessions = await _playbackSessions.getAll();

    final unownedSessions = sessions
        .where((session) => session.userId == null)
        .toList(growable: false);

    if (unownedSessions.isEmpty) {
      return const AnalyticsAccountAttachmentResult(
        sessionsAttached: 0,
        qualifiedPlaysAttached: 0,
      );
    }

    final sessionIds = unownedSessions
        .map((session) => session.id)
        .toList(growable: false);

    final plays = await _qualifiedPlays.getByPlaybackSessionIds(sessionIds);

    _validateQualifiedPlayOwnership(plays: plays, userId: normalizedUserId);

    for (final session in unownedSessions) {
      await _playbackSessions.save(session.copyWith(userId: normalizedUserId));
    }

    var qualifiedPlaysAttached = 0;

    for (final play in plays) {
      if (play.userId != null) {
        continue;
      }

      await _qualifiedPlays.save(play.copyWith(userId: normalizedUserId));

      qualifiedPlaysAttached++;
    }

    return AnalyticsAccountAttachmentResult(
      sessionsAttached: unownedSessions.length,
      qualifiedPlaysAttached: qualifiedPlaysAttached,
    );
  }

  void _validateQualifiedPlayOwnership({
    required List<QualifiedPlay> plays,
    required String userId,
  }) {
    for (final play in plays) {
      final owner = play.userId;

      if (owner != null && owner != userId) {
        throw StateError(
          'Qualified play ${play.id} belongs to a different user.',
        );
      }
    }
  }
}
