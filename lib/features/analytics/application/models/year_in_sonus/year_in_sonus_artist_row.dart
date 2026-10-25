import '../../../../library/application/models/library_artist.dart';
import 'year_in_sonus_ranked_entity.dart';

class YearInSonusArtistRow {
  const YearInSonusArtistRow({
    required this.artist,
    required this.name,
    required this.ranking,
  });

  final LibraryArtist? artist;

  final String name;

  final YearInSonusRankedEntity ranking;

  String get entityId => ranking.entityId;

  int get rank => ranking.rank;

  int get streams => ranking.streams;

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

    final songs = current.songCount == 1 ? 'song' : 'songs';
    final albums = current.albumCount == 1 ? 'album' : 'albums';
    return '${current.songCount} $songs / ${current.albumCount} $albums';
  }
}
