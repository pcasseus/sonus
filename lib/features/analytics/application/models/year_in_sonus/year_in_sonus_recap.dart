import '../analytics_behavior_metrics.dart';
import '../analytics_summary.dart';
import 'year_in_sonus_month.dart';
import 'year_in_sonus_ranked_entity.dart';

class YearInSonusRecap {
  const YearInSonusRecap({
    required this.year,
    required this.summary,
    required this.audibleListeningDuration,
    required this.behavior,
    required this.topTracks,
    required this.topArtists,
    required this.topAlbums,
    required this.months,
    required this.longestListeningStreakDays,
    this.newArtistIds = const [],
    this.newAlbumIds = const [],
  });

  final int year;

  final AnalyticsSummary summary;
  final Duration audibleListeningDuration;
  final AnalyticsBehaviorMetrics behavior;

  final List<YearInSonusRankedEntity> topTracks;
  final List<YearInSonusRankedEntity> topArtists;
  final List<YearInSonusRankedEntity> topAlbums;

  final List<YearInSonusMonth> months;

  final int longestListeningStreakDays;

  final List<String> newArtistIds;
  final List<String> newAlbumIds;

  int get newArtistCount => newArtistIds.length;

  int get newAlbumCount => newAlbumIds.length;

  double? get topTrackStreamShare {
    final totalStreams = summary.qualifiedStreamCount;
    final leader = topTrack;

    if (totalStreams <= 0 || leader == null) {
      return null;
    }

    return leader.streams / totalStreams;
  }

  double? get topArtistStreamShare {
    final totalStreams = summary.qualifiedStreamCount;
    final leader = topArtist;

    if (totalStreams <= 0 || leader == null) {
      return null;
    }

    return leader.streams / totalStreams;
  }

  double? get tracksPerArtist {
    final artistCount = summary.distinctArtistCount;

    if (artistCount <= 0) {
      return null;
    }

    return summary.distinctSongCount / artistCount;
  }

  YearInSonusRankedEntity? get topTrack =>
      topTracks.isEmpty ? null : topTracks.first;

  YearInSonusRankedEntity? get topArtist =>
      topArtists.isEmpty ? null : topArtists.first;

  YearInSonusRankedEntity? get topAlbum =>
      topAlbums.isEmpty ? null : topAlbums.first;

  YearInSonusMonth? get mostActiveMonth {
    YearInSonusMonth? result;

    for (final month in months) {
      final current = result;

      if (current == null ||
          month.streams > current.streams ||
          (month.streams == current.streams &&
              month.listeningDuration > current.listeningDuration) ||
          (month.streams == current.streams &&
              month.listeningDuration == current.listeningDuration &&
              month.month.isBefore(current.month))) {
        result = month;
      }
    }

    return result?.hasListening == true ? result : null;
  }

  bool get hasListening =>
      summary.hasListening || audibleListeningDuration > Duration.zero;
}
