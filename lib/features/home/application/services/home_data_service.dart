import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../../analytics/application/services/analytics_artist_listening_duration_service.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../library/application/models/library_track_order.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../models/home_popular_track.dart';
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

    final recentlyAddedAlbumsFuture = _library.getRecentlyAddedAlbums(
      sectionLimit,
    );

    final rankingsFuture = _analyticsRankings.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );

    final artistDurationsFuture = _artistListeningDurations.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );

    final recentlyAddedTracks = await recentlyAddedTracksFuture;
    final recentlyAddedAlbums = await recentlyAddedAlbumsFuture;
    final rankings = await rankingsFuture;
    final artistDurations = await artistDurationsFuture;

    final visibleRecentlyAddedTracks = recentlyAddedTracks
        .where((track) => track.isAvailable)
        .take(sectionLimit)
        .toList(growable: false);

    final popularTracks = await _buildPopularTracks(rankings.songs);

    final topArtists = await _buildTopArtists(
      rankings.artists,
      artistDurations,
    );

    return HomeSnapshot(
      recentlyAddedTracks: List.unmodifiable(visibleRecentlyAddedTracks),
      recentlyAddedAlbums: List.unmodifiable(recentlyAddedAlbums),
      weeklyPopularTracks: List.unmodifiable(popularTracks),
      weeklyTopArtists: List.unmodifiable(topArtists),
    );
  }

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
        ),
      );
    }

    return result;
  }
}
