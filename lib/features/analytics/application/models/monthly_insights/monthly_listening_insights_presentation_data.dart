import '../monthly_insights/monthly_album_insight_row.dart';
import '../monthly_insights/monthly_artist_insight_row.dart';
import '../monthly_insights/monthly_listening_insights.dart';
import '../monthly_insights/monthly_track_insight_row.dart';

class MonthlyListeningInsightsPresentationData {
  const MonthlyListeningInsightsPresentationData({
    required this.insights,
    required this.tracks,
    required this.artists,
    required this.albums,
  });

  final MonthlyListeningInsights insights;

  final List<MonthlyTrackInsightRow> tracks;
  final List<MonthlyArtistInsightRow> artists;
  final List<MonthlyAlbumInsightRow> albums;
}
