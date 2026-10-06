import '../../../../library/application/models/library_album.dart';
import 'year_in_sonus_ranked_entity.dart';

class YearInSonusAlbumRow {
  const YearInSonusAlbumRow({
    required this.album,
    required this.title,
    required this.artistName,
    required this.ranking,
  });

  final LibraryAlbum? album;

  final String title;
  final String artistName;

  final YearInSonusRankedEntity ranking;

  String get entityId => ranking.entityId;

  int get rank => ranking.rank;

  int get streams => ranking.streams;

  bool get hasCurrentLibraryEntity => album != null;

  String? get artworkPath => album?.artworkPath;
}
