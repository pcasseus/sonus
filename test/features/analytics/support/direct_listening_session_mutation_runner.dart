import 'package:sonus_next/features/analytics/application/services/listening_session_mutation_context.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_mutation_runner.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

class DirectListeningSessionMutationRunner
    implements ListeningSessionMutationRunner {
  DirectListeningSessionMutationRunner({
    required this.playbackSessions,
    required this.listeningSegments,
    required this.qualifiedPlays,
  });

  final PlaybackSessionRepository playbackSessions;
  final PlaybackListeningSegmentRepository listeningSegments;
  final QualifiedPlayRepository qualifiedPlays;

  bool failNextMutation = false;

  @override
  Future<T> run<T>(ListeningSessionMutationAction<T> action) {
    if (failNextMutation) {
      failNextMutation = false;
      return Future<T>.error(
        StateError('Injected listening-session mutation failure.'),
      );
    }

    return action(
      ListeningSessionMutationContext(
        playbackSessions: playbackSessions,
        listeningSegments: listeningSegments,
        qualifiedPlays: qualifiedPlays,
      ),
    );
  }
}
