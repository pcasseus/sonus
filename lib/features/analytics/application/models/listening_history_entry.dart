import '../../domain/entities/playback_session.dart';
import '../../domain/entities/qualified_play.dart';

class ListeningHistoryEntry {
  const ListeningHistoryEntry({required this.session, this.qualifiedPlay});

  final PlaybackSession session;
  final QualifiedPlay? qualifiedPlay;

  bool get isQualified => qualifiedPlay != null;

  DateTime? get qualifiedAt => qualifiedPlay?.qualifiedAt;
}
