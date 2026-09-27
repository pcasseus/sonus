import '../../../../core/database/app_database.dart';
import '../../application/services/listening_session_mutation_context.dart';
import '../../application/services/listening_session_mutation_runner.dart';
import '../daos/playback_listening_segment_dao.dart';
import '../daos/playback_session_dao.dart';
import '../daos/qualified_play_dao.dart';
import 'sqlite_playback_listening_segment_repository.dart';
import 'sqlite_playback_session_repository.dart';
import 'sqlite_qualified_play_repository.dart';

class ListeningSessionMutationTransactionRunner
    implements ListeningSessionMutationRunner {
  const ListeningSessionMutationTransactionRunner({required this.appDatabase});

  final AppDatabase appDatabase;

  @override
  Future<T> run<T>(ListeningSessionMutationAction<T> action) {
    return appDatabase.transaction((transaction) async {
      final context = ListeningSessionMutationContext(
        playbackSessions: SqlitePlaybackSessionRepository(
          PlaybackSessionDao(transaction),
        ),
        listeningSegments: SqlitePlaybackListeningSegmentRepository(
          PlaybackListeningSegmentDao(transaction),
        ),
        qualifiedPlays: SqliteQualifiedPlayRepository(
          QualifiedPlayDao(transaction),
        ),
      );

      return action(context);
    });
  }
}
