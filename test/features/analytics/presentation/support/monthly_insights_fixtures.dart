import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_album_insight_row.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_artist_insight_row.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_daily_listening.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_entity_listening_durations.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_hourly_listening.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_distribution.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights_presentation_data.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_track_insight_row.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_enrichment_service.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_service.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

/// October 2026 with 60 streams (September: 40), listening on alternate
/// days, an evening peak at 8 PM and three ranked tracks, artists and
/// albums. Values are fixtures for presentation tests only. [hours]
/// replaces the hourly distribution.
MonthlyListeningInsights octoberInsights({
  List<MonthlyHourlyListening>? hours,
}) {
  final selected = DateTime(2026, 10);
  final window = AnalyticsTimeWindow(
    startUtc: selected.toUtc(),
    endUtc: DateTime(2026, 11).toUtc(),
  );

  AnalyticsSummary summary(AnalyticsTimeWindow w, int streams, int songs) =>
      AnalyticsSummary(
        period: AnalyticsPeriod.month,
        window: w,
        qualifiedStreamCount: streams,
        qualifiedListeningDuration: const Duration(hours: 5),
        distinctSongCount: songs,
        distinctArtistCount: 6,
        distinctAlbumCount: 5,
        firstQualifiedAt: w.startUtc,
        lastQualifiedAt: w.startUtc,
      );

  return MonthlyListeningInsights(
    selectedMonth: selected,
    previousMonth: DateTime(2026, 9),
    currentSummary: summary(window, 60, 12),
    previousSummary: summary(
      AnalyticsTimeWindow(
        startUtc: DateTime(2026, 9).toUtc(),
        endUtc: selected.toUtc(),
      ),
      40,
      10,
    ),
    currentAudibleListeningDuration: const Duration(hours: 5),
    previousAudibleListeningDuration: const Duration(hours: 4),
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.month,
      window: window,
      sessionCount: 70,
      endedSessionCount: 70,
      completedSessionCount: 55,
      skippedSessionCount: 10,
      stoppedSessionCount: 5,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: window.startUtc,
      lastSessionStartedAt: window.startUtc,
      activeQualifiedDayCount: 12,
      averageQualifiedStreamsPerActiveDay: 5,
      averageQualifiedStreamsPerCalendarDay: 60 / 31,
      peakDay: null,
    ),
    distribution: MonthlyListeningDistribution(
      days: [
        for (var day = 1; day <= 24; day += 2)
          MonthlyDailyListening(
            localDate: DateTime(2026, 10, day),
            streams: 3 + day % 4,
            listeningDuration: Duration(minutes: 20 + day),
          ),
      ],
      hours:
          hours ??
          const [
            MonthlyHourlyListening(
              hour: 8,
              streams: 6,
              listeningDuration: Duration(minutes: 30),
            ),
            MonthlyHourlyListening(
              hour: 20,
              streams: 30,
              listeningDuration: Duration(hours: 2),
            ),
          ],
    ),
    entityListeningDurations: const MonthlyEntityListeningDurations(
      songs: {},
      artists: {},
      albums: {},
    ),
    songs: const [],
    artists: const [],
    albums: const [],
  );
}

class FixtureInsightsLoader implements MonthlyListeningInsightsLoader {
  const FixtureInsightsLoader(this.result);

  final MonthlyListeningInsights result;

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async => result;
}

/// Builds rows the way the real enricher does, with optional artwork and
/// [rowCount] ranked tracks, artists and albums.
class FixtureInsightsEnricher implements MonthlyListeningInsightsEnricher {
  const FixtureInsightsEnricher({this.artworkPath, this.rowCount = 3});

  final String? artworkPath;
  final int rowCount;

  @override
  Future<MonthlyListeningInsightsPresentationData> enrich(
    MonthlyListeningInsights insights,
  ) async {
    MonthlyRankedEntity rank(String id, int r) => MonthlyRankedEntity(
      entityId: id,
      rank: r,
      previousRank: r,
      streams: 20 - r,
      previousStreams: 10,
      lifetimeStreams: 100,
    );

    return MonthlyListeningInsightsPresentationData(
      insights: insights,
      tracks: [
        for (var i = 1; i <= rowCount; i++)
          MonthlyTrackInsightRow(
            track: LibraryTrack(
              songId: 't$i',
              title: 'Track $i',
              artistId: 'a$i',
              artistName: 'Artist $i',
              albumId: 'al$i',
              albumTitle: 'Album $i',
              albumEditionId: 'e$i',
              albumEditionTitle: 'Standard',
              albumEditionType: AlbumEditionType.standard,
              trackNumber: 1,
              durationSeconds: 200,
              isSingle: false,
              featuredArtists: const [],
              dateAdded: DateTime(2026),
              isAvailable: true,
              isSongBlocked: false,
              filePath: '/music/t$i.mp3',
              artworkPath: artworkPath,
            ),
            title: 'Track $i',
            artistName: 'Artist $i',
            albumTitle: 'Album $i',
            ranking: rank('t$i', i),
            listeningDuration: const Duration(minutes: 30),
          ),
      ],
      artists: [
        for (var i = 1; i <= rowCount; i++)
          MonthlyArtistInsightRow(
            artist: LibraryArtist(
              artistId: 'a$i',
              name: 'Artist $i',
              albumCount: 1,
              songCount: 3,
              dateAdded: DateTime(2026),
              topArtistsArtworkPath: artworkPath,
            ),
            name: 'Artist $i',
            ranking: rank('a$i', i),
            listeningDuration: const Duration(minutes: 40),
          ),
      ],
      albums: [
        for (var i = 1; i <= rowCount; i++)
          MonthlyAlbumInsightRow(
            album: LibraryAlbum(
              albumId: 'al$i',
              title: 'Album $i',
              artistId: 'a$i',
              artistName: 'Artist $i',
              trackCount: 10,
              dateAdded: DateTime(2026),
              artworkPath: artworkPath,
            ),
            title: 'Album $i',
            artistName: 'Artist $i',
            ranking: rank('al$i', i),
            listeningDuration: const Duration(minutes: 50),
          ),
      ],
    );
  }
}
