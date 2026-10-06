import '../../../../library/application/models/library_track.dart';
import 'year_in_sonus_ranked_entity.dart';

class YearInSonusTrackRow {
  const YearInSonusTrackRow({
    required this.track,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.ranking,
  });

  final LibraryTrack? track;

  final String title;
  final String artistName;
  final String albumTitle;

  final YearInSonusRankedEntity ranking;

  String get entityId => ranking.entityId;

  int get rank => ranking.rank;

  int get streams => ranking.streams;

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
}
