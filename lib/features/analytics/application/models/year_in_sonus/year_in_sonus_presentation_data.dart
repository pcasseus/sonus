import 'year_in_sonus_album_row.dart';
import 'year_in_sonus_artist_row.dart';
import 'year_in_sonus_month_row.dart';
import 'year_in_sonus_recap.dart';
import 'year_in_sonus_track_row.dart';

class YearInSonusPresentationData {
  const YearInSonusPresentationData({
    required this.recap,
    required this.tracks,
    required this.artists,
    required this.albums,
    required this.months,
  });

  final YearInSonusRecap recap;

  final List<YearInSonusTrackRow> tracks;
  final List<YearInSonusArtistRow> artists;
  final List<YearInSonusAlbumRow> albums;
  final List<YearInSonusMonthRow> months;
}
