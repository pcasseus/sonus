import 'year_in_sonus_month.dart';

class YearInSonusMonthRow {
  const YearInSonusMonthRow({
    required this.month,
    required this.topSongTitle,
    required this.topArtistName,
  });

  final YearInSonusMonth month;

  final String? topSongTitle;
  final String? topArtistName;
}
