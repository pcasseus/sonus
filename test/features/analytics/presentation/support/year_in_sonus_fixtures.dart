import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_peak_day.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_album_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_artist_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month_row.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_presentation_data.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_recap.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_track_row.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_enrichment_service.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_service.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

// Year in Sonus fixtures for presentation tests: a 2026 recap with 1,234
// streams, March as the peak month and ranked artists, tracks and albums.

const windowlessYear = AnalyticsTimeWindow(startUtc: null, endUtc: null);

YearInSonusRecap richYearRecap(int year) {
  return YearInSonusRecap(
    year: year,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: windowlessYear,
      qualifiedStreamCount: 1234,
      qualifiedListeningDuration: Duration(hours: 80),
      distinctSongCount: 300,
      distinctArtistCount: 60,
      distinctAlbumCount: 80,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: const Duration(hours: 82, minutes: 30),
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: windowlessYear,
      sessionCount: 1400,
      endedSessionCount: 1400,
      completedSessionCount: 1100,
      skippedSessionCount: 250,
      stoppedSessionCount: 50,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 150,
      averageQualifiedStreamsPerActiveDay: 1234 / 150,
      averageQualifiedStreamsPerCalendarDay: 1234 / 365,
      peakDay: AnalyticsPeakDay(
        localDate: DateTime(year, 3, 14),
        qualifiedStreamCount: 42,
      ),
    ),
    topTracks: const [
      YearInSonusRankedEntity(entityId: 's1', rank: 1, streams: 90),
      YearInSonusRankedEntity(entityId: 's2', rank: 2, streams: 60),
    ],
    topArtists: const [
      YearInSonusRankedEntity(entityId: 'ar1', rank: 1, streams: 150),
      YearInSonusRankedEntity(entityId: 'ar2', rank: 2, streams: 40),
    ],
    topAlbums: const [
      YearInSonusRankedEntity(entityId: 'al1', rank: 1, streams: 70),
    ],
    months: [
      for (var month = 1; month <= 12; month++)
        YearInSonusMonth(
          month: DateTime(year, month),
          streams: month == 3 ? 200 : 80 + month,
          listeningDuration: month == 3
              ? const Duration(hours: 10)
              : Duration(hours: 5, minutes: month),
          topSongId: 's1',
          topArtistId: 'ar1',
        ),
    ],
    longestListeningStreakDays: 12,
    newArtistIds: const ['ar7', 'ar8'],
    newAlbumIds: const ['al7', 'al8', 'al9'],
  );
}

YearInSonusRecap emptyYearRecap(int year) {
  return YearInSonusRecap(
    year: year,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: windowlessYear,
      qualifiedStreamCount: 0,
      qualifiedListeningDuration: Duration.zero,
      distinctSongCount: 0,
      distinctArtistCount: 0,
      distinctAlbumCount: 0,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: Duration.zero,
    behavior: const AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: windowlessYear,
      sessionCount: 0,
      endedSessionCount: 0,
      completedSessionCount: 0,
      skippedSessionCount: 0,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 0,
      averageQualifiedStreamsPerActiveDay: 0,
      averageQualifiedStreamsPerCalendarDay: 0,
      peakDay: null,
    ),
    topTracks: const [],
    topArtists: const [],
    topAlbums: const [],
    months: const [],
    longestListeningStreakDays: 0,
  );
}

class FixtureYearLoader implements YearInSonusLoader {
  FixtureYearLoader(this.results, {this.error});

  final Map<int, YearInSonusRecap> results;
  final Object? error;
  final List<int> requestedYears = [];

  @override
  Future<YearInSonusRecap> load({required int year}) async {
    requestedYears.add(year);

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return results[year] ?? emptyYearRecap(year);
  }
}

/// Builds rows the way the real enricher does: library entities when they
/// exist, ranking order from the recap.
class FixtureYearEnricher implements YearInSonusEnricher {
  const FixtureYearEnricher({this.artworkPath});

  final String? artworkPath;

  @override
  Future<YearInSonusPresentationData> enrich(YearInSonusRecap recap) async {
    return YearInSonusPresentationData(
      recap: recap,
      tracks: [
        for (final ranking in recap.topTracks)
          YearInSonusTrackRow(
            track: fixtureYearTrack(ranking.entityId, artworkPath: artworkPath),
            title: ranking.entityId == 's1' ? 'Song One' : 'Song Two',
            artistName: 'Artist One',
            albumTitle: 'Album One',
            ranking: ranking,
          ),
      ],
      artists: [
        for (final ranking in recap.topArtists)
          YearInSonusArtistRow(
            artist: LibraryArtist(
              artistId: ranking.entityId,
              name: ranking.entityId == 'ar1' ? 'Artist One' : 'Artist Two',
              albumCount: 2,
              songCount: 10,
              dateAdded: DateTime(2026),
              topArtistsArtworkPath: artworkPath,
            ),
            name: ranking.entityId == 'ar1' ? 'Artist One' : 'Artist Two',
            ranking: ranking,
          ),
      ],
      albums: [
        for (final ranking in recap.topAlbums)
          YearInSonusAlbumRow(
            album: LibraryAlbum(
              albumId: ranking.entityId,
              title: 'Album One',
              artistId: 'ar1',
              artistName: 'Artist One',
              trackCount: 10,
              dateAdded: DateTime(2026),
              artworkPath: artworkPath,
            ),
            title: 'Album One',
            artistName: 'Artist One',
            ranking: ranking,
          ),
      ],
      months: [
        for (final month in recap.months)
          YearInSonusMonthRow(
            month: month,
            topSongTitle: 'Song One',
            topArtistName: 'Artist One',
          ),
      ],
    );
  }
}

LibraryTrack fixtureYearTrack(String id, {String? artworkPath}) {
  return LibraryTrack(
    songId: id,
    title: id,
    artistId: 'ar1',
    artistName: 'Artist One',
    albumId: 'al1',
    albumTitle: 'Album One',
    albumEditionId: 'e1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026),
    isAvailable: true,
    isSongBlocked: false,
    filePath: '/music/$id.mp3',
    artworkPath: artworkPath,
  );
}
