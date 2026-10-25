import 'dart:math' as math;

import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../../analytics/application/services/analytics_artist_listening_duration_service.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/models/library_track_order.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../models/home_popular_track.dart';
import '../models/home_ranking_week.dart';
import '../models/home_snapshot.dart';
import '../models/home_top_artist.dart';

class HomeDataService {
  const HomeDataService({
    required this._library,
    required this._analyticsRankings,
    required this._artistListeningDurations,
    this.sectionLimit = 6,
  });

  final LibraryQueryRepository _library;
  final AnalyticsEntityRankingService _analyticsRankings;
  final AnalyticsArtistListeningDurationService _artistListeningDurations;

  final int sectionLimit;

  Future<HomeSnapshot> load({required DateTime referenceLocal}) async {
    if (sectionLimit <= 0) {
      throw StateError('Home section limit must be greater than zero.');
    }

    final recentlyAddedTracksFuture = _library.getTracks(
      order: LibraryTrackOrder.dateAdded,
    );

    final albumsFuture = _library.getAlbums();

    // The same time a week earlier: calendar days, so a DST change can't
    // land it in the wrong week.
    final lastWeekReference = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day - 7,
      referenceLocal.hour,
      referenceLocal.minute,
    );

    final rankingsFuture = _analyticsRankings.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );
    final lastWeekRankingsFuture = _analyticsRankings.load(
      period: AnalyticsPeriod.week,
      referenceLocal: lastWeekReference,
    );

    final artistDurationsFuture = _artistListeningDurations.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );
    final lastWeekArtistDurationsFuture = _artistListeningDurations.load(
      period: AnalyticsPeriod.week,
      referenceLocal: lastWeekReference,
    );

    final recentlyAddedTracks = await recentlyAddedTracksFuture;
    final albums = await albumsFuture;
    final rankings = await rankingsFuture;
    final lastWeekRankings = await lastWeekRankingsFuture;
    final artistDurations = await artistDurationsFuture;
    final lastWeekArtistDurations = await lastWeekArtistDurationsFuture;

    final availableTracks = recentlyAddedTracks
        .where(_hasAvailableMedia)
        .toList(growable: false);

    final visibleRecentlyAddedTracks = availableTracks
        .take(sectionLimit)
        .toList(growable: false);

    final availableAlbumIds = availableTracks
        .map((track) => track.albumId)
        .toSet();

    final availableArtistIds = availableTracks
        .map((track) => track.artistId)
        .toSet();

    for (final album in albums) {
      if (availableAlbumIds.contains(album.albumId)) {
        availableArtistIds.add(album.artistId);
      }
    }

    final visibleRecentlyAddedAlbums =
        albums
            .where((album) => availableAlbumIds.contains(album.albumId))
            .toList(growable: false)
          ..sort(_compareRecentlyAddedAlbums);

    final popularTracks = _chooseWeek(
      thisWeek: await _buildPopularTracks(rankings.songs),
      lastWeek: await _buildPopularTracks(lastWeekRankings.songs),
    );

    final topArtists = _chooseWeek(
      thisWeek: await _buildTopArtists(
        rankings.artists,
        artistDurations,
        availableArtistIds,
      ),
      lastWeek: await _buildTopArtists(
        lastWeekRankings.artists,
        lastWeekArtistDurations,
        availableArtistIds,
      ),
    );

    return HomeSnapshot(
      recentlyAddedTracks: List.unmodifiable(visibleRecentlyAddedTracks),
      recentlyAddedAlbums: List.unmodifiable(
        visibleRecentlyAddedAlbums.take(sectionLimit),
      ),
      weeklyPopularTracks: List.unmodifiable(popularTracks.entries),
      weeklyTopArtists: List.unmodifiable(topArtists.entries),
      popularTracksWeek: popularTracks.week,
      topArtistsWeek: topArtists.week,
    );
  }

  /// Shows this week once it has enough entries, otherwise last week's
  /// completed ranking.
  ///
  /// Enough is three entries, or as many as last week had if fewer, but
  /// never one: a single play never replaces a ranking. With nothing last
  /// week, this week shows from its first entry. Each section decides on
  /// its own, and last week is only ever the week just completed, so the
  /// fallback never outlives the current week.
  ({List<T> entries, HomeRankingWeek week}) _chooseWeek<T>({
    required List<T> thisWeek,
    required List<T> lastWeek,
  }) {
    if (lastWeek.isEmpty) {
      return (entries: thisWeek, week: HomeRankingWeek.thisWeek);
    }

    final needed = math.min(
      sectionLimit,
      math.max(
        _minimumEntriesToReplace,
        math.min(_readyEntries, lastWeek.length),
      ),
    );

    return thisWeek.length >= needed
        ? (entries: thisWeek, week: HomeRankingWeek.thisWeek)
        : (entries: lastWeek, week: HomeRankingWeek.lastWeek);
  }

  /// Entries at which this week's ranking is ready to replace last week's.
  static const int _readyEntries = 3;

  /// Fewest entries that ever replace last week's ranking.
  static const int _minimumEntriesToReplace = 2;

  Future<List<HomePopularTrack>> _buildPopularTracks(
    List<AnalyticsRankedEntity> rankings,
  ) async {
    final result = <HomePopularTrack>[];

    for (final ranking in rankings) {
      if (result.length >= sectionLimit) {
        break;
      }

      final track = await _library.getTrackById(ranking.entityId);

      if (track == null || track.isBlocked) {
        continue;
      }

      result.add(
        HomePopularTrack(
          track: track,
          rank: result.length + 1,
          qualifiedStreamCount: ranking.qualifiedStreamCount,
        ),
      );
    }

    return result;
  }

  Future<List<HomeTopArtist>> _buildTopArtists(
    List<AnalyticsRankedEntity> rankings,
    Map<String, Duration> artistDurations,
    Set<String> availableArtistIds,
  ) async {
    final result = <HomeTopArtist>[];

    for (final ranking in rankings) {
      if (result.length >= sectionLimit) {
        break;
      }

      final artist = await _library.getArtistById(ranking.entityId);

      if (artist == null) {
        continue;
      }

      result.add(
        HomeTopArtist(
          artist: artist,
          rank: result.length + 1,
          qualifiedStreamCount: ranking.qualifiedStreamCount,
          weeklyListeningDuration:
              artistDurations[ranking.entityId] ?? Duration.zero,
          isAvailable: availableArtistIds.contains(artist.artistId),
        ),
      );
    }

    return result;
  }

  static bool _hasAvailableMedia(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  static int _compareRecentlyAddedAlbums(LibraryAlbum a, LibraryAlbum b) {
    final createdCompare = b.dateAdded.compareTo(a.dateAdded);

    if (createdCompare != 0) {
      return createdCompare;
    }

    final titleCompare = a.title.toLowerCase().compareTo(b.title.toLowerCase());

    if (titleCompare != 0) {
      return titleCompare;
    }

    return a.albumId.compareTo(b.albumId);
  }
}
