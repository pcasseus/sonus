import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../../analytics/application/services/analytics_artist_listening_duration_service.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
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

    final albumsFuture = _library.getAlbums();

    final rankingsFuture = _analyticsRankings.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );

    final artistDurationsFuture = _artistListeningDurations.load(
      period: AnalyticsPeriod.week,
      referenceLocal: referenceLocal,
    );

    final recentlyAddedTracks = await recentlyAddedTracksFuture;
    final albums = await albumsFuture;
    final rankings = await rankingsFuture;
    final artistDurations = await artistDurationsFuture;

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

    final popularTracks = await _buildPopularTracks(rankings.songs);

    final topArtists = await _buildTopArtists(
      rankings.artists,
      artistDurations,
      availableArtistIds,
    );

    return HomeSnapshot(
      recentlyAddedTracks: List.unmodifiable(visibleRecentlyAddedTracks),
      recentlyAddedAlbums: List.unmodifiable(
        visibleRecentlyAddedAlbums.take(sectionLimit),
      ),
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
