import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_month.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_recap.dart';

void main() {
  group('YearInSonusRecap', () {
    test('exposes #1 track, artist, and album', () {
      final recap = _recap(
        topTracks: const [
          YearInSonusRankedEntity(entityId: 'song_1', rank: 1, streams: 50),
        ],
        topArtists: const [
          YearInSonusRankedEntity(entityId: 'artist_1', rank: 1, streams: 75),
        ],
        topAlbums: const [
          YearInSonusRankedEntity(entityId: 'album_1', rank: 1, streams: 60),
        ],
      );

      expect(recap.topTrack?.entityId, 'song_1');
      expect(recap.topArtist?.entityId, 'artist_1');
      expect(recap.topAlbum?.entityId, 'album_1');
    });

    test('returns null top entities when rankings are empty', () {
      final recap = _recap();

      expect(recap.topTrack, isNull);
      expect(recap.topArtist, isNull);
      expect(recap.topAlbum, isNull);
    });

    test('mostActiveMonth prefers higher streams', () {
      final recap = _recap(
        months: [
          YearInSonusMonth(
            month: DateTime(2026, 1),
            streams: 10,
            topSongId: null,
            topArtistId: null,
          ),
          YearInSonusMonth(
            month: DateTime(2026, 2),
            streams: 20,
            topSongId: null,
            topArtistId: null,
          ),
        ],
      );

      expect(recap.mostActiveMonth?.month.month, DateTime.february);
    });

    test('mostActiveMonth uses earlier month for stream ties', () {
      final recap = _recap(
        months: [
          YearInSonusMonth(
            month: DateTime(2026, 1),
            streams: 20,
            topSongId: null,
            topArtistId: null,
          ),
          YearInSonusMonth(
            month: DateTime(2026, 2),
            streams: 20,
            topSongId: null,
            topArtistId: null,
          ),
        ],
      );

      expect(recap.mostActiveMonth?.month.month, DateTime.january);
    });

    test('mostActiveMonth is null when the year has no listening', () {
      final recap = _recap(
        months: [
          YearInSonusMonth(
            month: DateTime(2026, 1),
            streams: 0,
            topSongId: null,
            topArtistId: null,
          ),
          YearInSonusMonth(
            month: DateTime(2026, 2),
            streams: 0,
            topSongId: null,
            topArtistId: null,
          ),
        ],
      );

      expect(recap.mostActiveMonth, isNull);
    });

    test('mostActiveMonth uses listening duration as stream tie-break', () {
      final recap = _recap(
        months: [
          YearInSonusMonth(
            month: DateTime(2026, 1),
            streams: 20,
            listeningDuration: Duration(hours: 3),
            topSongId: null,
            topArtistId: null,
          ),
          YearInSonusMonth(
            month: DateTime(2026, 2),
            streams: 20,
            listeningDuration: Duration(hours: 5),
            topSongId: null,
            topArtistId: null,
          ),
        ],
      );

      expect(recap.mostActiveMonth?.month.month, DateTime.february);
    });

    test('derives Sonus signature metrics from annual truth', () {
      final recap = _recap(
        qualifiedStreamCount: 200,
        distinctSongCount: 80,
        distinctArtistCount: 20,
        topTracks: const [
          YearInSonusRankedEntity(entityId: 'song_1', rank: 1, streams: 50),
        ],
        topArtists: const [
          YearInSonusRankedEntity(entityId: 'artist_1', rank: 1, streams: 80),
        ],
      );

      expect(recap.topTrackStreamShare, 0.25);
      expect(recap.topArtistStreamShare, 0.40);
      expect(recap.tracksPerArtist, 4);
    });

    test('Sonus signature metrics are null when unavailable', () {
      final recap = _recap();

      expect(recap.topTrackStreamShare, isNull);
      expect(recap.topArtistStreamShare, isNull);
      expect(recap.tracksPerArtist, isNull);
    });

    test('hasListening also reflects audible listening duration', () {
      final recap = _recap(
        audibleListeningDuration: const Duration(minutes: 12),
      );

      expect(recap.hasListening, isTrue);
    });
  });
}

YearInSonusRecap _recap({
  Duration audibleListeningDuration = Duration.zero,
  int qualifiedStreamCount = 0,
  int distinctSongCount = 0,
  int distinctArtistCount = 0,
  int distinctAlbumCount = 0,
  List<YearInSonusRankedEntity> topTracks = const [],
  List<YearInSonusRankedEntity> topArtists = const [],
  List<YearInSonusRankedEntity> topAlbums = const [],
  List<YearInSonusMonth> months = const [],
}) {
  return YearInSonusRecap(
    year: 2026,
    summary: AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
      qualifiedStreamCount: qualifiedStreamCount,
      qualifiedListeningDuration: Duration.zero,
      distinctSongCount: distinctSongCount,
      distinctArtistCount: distinctArtistCount,
      distinctAlbumCount: distinctAlbumCount,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: audibleListeningDuration,
    behavior: const AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
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
    topTracks: topTracks,
    topArtists: topArtists,
    topAlbums: topAlbums,
    months: months,
    longestListeningStreakDays: 0,
  );
}
