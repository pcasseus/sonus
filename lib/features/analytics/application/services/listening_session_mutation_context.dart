import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';

class ListeningSessionMutationContext {
  const ListeningSessionMutationContext({
    required this.playbackSessions,
    required this.listeningSegments,
    required this.qualifiedPlays,
  });

  final PlaybackSessionRepository playbackSessions;
  final PlaybackListeningSegmentRepository listeningSegments;
  final QualifiedPlayRepository qualifiedPlays;
}
