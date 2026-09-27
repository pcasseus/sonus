// ignore_for_file: prefer_initializing_formals

import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../models/analytics_period.dart';
import '../models/analytics_summary.dart';
import '../models/analytics_time_window.dart';
import 'analytics_time_window_resolver.dart';

class AnalyticsSummaryService {
  const AnalyticsSummaryService({
    required QualifiedPlayRepository qualifiedPlays,
    AnalyticsTimeWindowResolver timeWindowResolver =
        const AnalyticsTimeWindowResolver(),
  }) : _qualifiedPlays = qualifiedPlays,
       _timeWindowResolver = timeWindowResolver;

  final QualifiedPlayRepository _qualifiedPlays;
  final AnalyticsTimeWindowResolver _timeWindowResolver;

  Future<AnalyticsSummary> load({
    required AnalyticsPeriod period,
    required DateTime referenceLocal,
  }) async {
    final window = _timeWindowResolver.resolve(
      period: period,
      referenceLocal: referenceLocal,
    );

    final plays = await _qualifiedPlays.getAll(
      qualifiedAtOrAfter: window.startUtc,
      qualifiedBefore: window.endUtc,
    );

    return _buildSummary(period: period, window: window, plays: plays);
  }

  AnalyticsSummary _buildSummary({
    required AnalyticsPeriod period,
    required AnalyticsTimeWindow window,
    required List<QualifiedPlay> plays,
  }) {
    final songIds = <String>{};
    final artistIds = <String>{};
    final albumIds = <String>{};

    var totalListeningMilliseconds = 0;

    DateTime? firstQualifiedAt;
    DateTime? lastQualifiedAt;

    for (final play in plays) {
      songIds.add(play.songId);
      artistIds.add(play.artistId);
      albumIds.add(play.albumId);

      totalListeningMilliseconds += play.listenedDuration.inMilliseconds;

      final qualifiedAt = play.qualifiedAt.toUtc();

      if (firstQualifiedAt == null || qualifiedAt.isBefore(firstQualifiedAt)) {
        firstQualifiedAt = qualifiedAt;
      }

      if (lastQualifiedAt == null || qualifiedAt.isAfter(lastQualifiedAt)) {
        lastQualifiedAt = qualifiedAt;
      }
    }

    return AnalyticsSummary(
      period: period,
      window: window,
      qualifiedStreamCount: plays.length,
      qualifiedListeningDuration: Duration(
        milliseconds: totalListeningMilliseconds,
      ),
      distinctSongCount: songIds.length,
      distinctArtistCount: artistIds.length,
      distinctAlbumCount: albumIds.length,
      firstQualifiedAt: firstQualifiedAt,
      lastQualifiedAt: lastQualifiedAt,
    );
  }
}
