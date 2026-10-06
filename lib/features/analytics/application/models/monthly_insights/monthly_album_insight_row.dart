import '../../../../library/application/models/library_album.dart';
import 'monthly_ranked_entity.dart';

class MonthlyAlbumInsightRow {
  const MonthlyAlbumInsightRow({
    required this.album,
    required this.title,
    required this.artistName,
    required this.ranking,
    required this.listeningDuration,
  });

  final LibraryAlbum? album;

  final String title;
  final String artistName;

  final MonthlyRankedEntity ranking;
  final Duration listeningDuration;

  String get entityId => ranking.entityId;

  bool get hasCurrentLibraryEntity => album != null;

  String? get artworkPath => album?.artworkPath;

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
