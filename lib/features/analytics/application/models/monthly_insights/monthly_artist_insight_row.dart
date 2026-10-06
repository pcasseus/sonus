import '../../../../library/application/models/library_artist.dart';
import 'monthly_ranked_entity.dart';

class MonthlyArtistInsightRow {
  const MonthlyArtistInsightRow({
    required this.artist,
    required this.name,
    required this.ranking,
    required this.listeningDuration,
  });

  final LibraryArtist? artist;
  final String name;

  final MonthlyRankedEntity ranking;
  final Duration listeningDuration;

  String get entityId => ranking.entityId;

  bool get hasCurrentLibraryEntity => artist != null;

  String? get artworkPath {
    final current = artist;

    if (current == null) {
      return null;
    }

    final topArtists = current.topArtistsArtworkPath?.trim();

    if (topArtists != null && topArtists.isNotEmpty) {
      return current.topArtistsArtworkPath;
    }

    return current.headerArtworkPath;
  }

  String get subtitle {
    final current = artist;

    if (current == null) {
      return 'Historical artist';
    }

    return '${current.songCount} songs / ${current.albumCount} albums';
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
