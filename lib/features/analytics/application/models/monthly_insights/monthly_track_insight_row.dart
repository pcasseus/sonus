import '../../../../library/application/models/library_track.dart';
import 'monthly_ranked_entity.dart';

class MonthlyTrackInsightRow {
  const MonthlyTrackInsightRow({
    required this.track,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.ranking,
    required this.listeningDuration,
  });

  final LibraryTrack? track;

  final String title;
  final String artistName;
  final String albumTitle;

  final MonthlyRankedEntity ranking;
  final Duration listeningDuration;

  String get entityId => ranking.entityId;

  String? get artworkPath => track?.artworkPath;

  bool get hasCurrentLibraryEntity => track != null;

  bool get isBlocked => track?.isBlocked ?? false;

  bool get isAvailable => track?.isAvailable ?? false;

  bool get canPlay {
    final current = track;

    if (current == null || current.isBlocked || !current.isAvailable) {
      return false;
    }

    final path = current.filePath?.trim();

    return path != null && path.isNotEmpty;
  }

  int get rank => ranking.rank;
  int? get previousRank => ranking.previousRank;
  int? get rankMovement => ranking.rankMovement;

  int get streams => ranking.streams;
  int get previousStreams => ranking.previousStreams;
  int get lifetimeStreams => ranking.lifetimeStreams;

  int get streamChange => ranking.streamChange.absoluteChange;
  double? get streamPercentChange => ranking.streamChange.percentChange;

  bool get isNew => ranking.isNew;
}
