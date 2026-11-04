import 'dart:developer' as developer;

import '../../../analytics/application/models/analytics_entity_rankings.dart';
import '../../../analytics/application/models/analytics_period.dart';
import '../../../analytics/application/models/analytics_ranked_entity.dart';
import '../../../analytics/application/services/analytics_artist_listening_duration_service.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../analytics/domain/repositories/playback_listening_segment_repository.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../application/models/library_track.dart';
import '../../application/models/song_artist_credit_link.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/library_organization_service.dart';
import '../models/artist_library_statistics.dart';
import '../models/artist_profile_sections.dart';

/// Loads every artist's statistics at once for the Film Reel and Artist
/// Roster (UI redesign D1). Read-only: it reads the library and listening
/// history, and never writes, backfills or recalculates anything.
///
/// Each value has the Artist Profile's definition, from the same sources:
/// - counts: [LibraryQueryRepository.getArtists];
/// - rank and qualified streams: the all-time [AnalyticsEntityRankingService]
///   with the library's [OrganizationArtistAttribution];
/// - listening time: the all-time [AnalyticsArtistListeningDurationService]
///   with the same attribution;
/// - top track: [ArtistProfileSections.topTracks] over the catalogue the
///   profile builds (main credits plus other performers' songs on the
///   artist's own releases; a contributor's appearances instead).
///
/// The profile reads its catalogue with several queries per artist; here
/// every source is read once, so the cost does not grow with the number of
/// artists in queries, only in the in-memory pass.
class ArtistLibraryStatisticsService {
  ArtistLibraryStatisticsService({
    required this._library,
    this._qualifiedPlays,
    this._playbackSessions,
    this._listeningSegments,
    this._organization,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryQueryRepository _library;
  final QualifiedPlayRepository? _qualifiedPlays;
  final PlaybackSessionRepository? _playbackSessions;
  final PlaybackListeningSegmentRepository? _listeningSegments;
  final LibraryOrganizationService? _organization;
  final DateTime Function() _clock;

  Future<ArtistLibraryStatisticsSnapshot> load() async {
    final artists = await _library.getArtists();
    if (artists.isEmpty) return ArtistLibraryStatisticsSnapshot.empty;

    final organizationService = _organization;
    final organization = await _loadOrganization();
    final attribution = organizationService == null
        ? null
        : OrganizationArtistAttribution(organizationService);

    final rankings = await _loadRankings(attribution);
    final listened = await _loadListening(attribution);

    final artistIndex = <String, AnalyticsRankedEntity>{};
    final artistRank = <String, int>{};
    if (rankings != null) {
      for (final (index, ranked) in rankings.artists.indexed) {
        artistIndex[ranked.entityId] = ranked;
        artistRank[ranked.entityId] = index + 1;
      }
    }

    final topTracks = rankings == null
        ? const <String, ArtistTopTrack>{}
        : await _topTracks(
            artistIds: [for (final artist in artists) artist.artistId],
            rankedSongs: rankings.songs,
            organization: organization,
          );

    return ArtistLibraryStatisticsSnapshot([
      for (final artist in artists)
        () {
          final ranked = artistIndex[artist.artistId];
          final streams = ranked?.qualifiedStreamCount ?? 0;
          return ArtistLibraryStatistics(
            artist: artist,
            // As ArtistProfileSections.standing: no rank without streams.
            rank: streams > 0 ? artistRank[artist.artistId] : null,
            qualifiedStreams: streams > 0 ? streams : 0,
            listened: listened == null
                ? null
                : listened[artist.artistId] ?? Duration.zero,
            topTrack: topTracks[artist.artistId],
          );
        }(),
    ]);
  }

  /// As the profile: unreadable organization counts as none.
  Future<ArtistLibraryOrganization?> _loadOrganization() async {
    try {
      return await _organization?.load();
    } catch (error, stackTrace) {
      _log('Library organization could not be read', error, stackTrace);
      return null;
    }
  }

  Future<AnalyticsEntityRankings?> _loadRankings(
    OrganizationArtistAttribution? attribution,
  ) async {
    final qualifiedPlays = _qualifiedPlays;
    if (qualifiedPlays == null) return null;
    try {
      return await AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ).load(period: AnalyticsPeriod.lifetime, referenceLocal: _clock());
    } catch (error, stackTrace) {
      _log('Artists could not be ranked', error, stackTrace);
      return null;
    }
  }

  /// Null when listening history is not available or cannot be read.
  Future<Map<String, Duration>?> _loadListening(
    OrganizationArtistAttribution? attribution,
  ) async {
    final sessions = _playbackSessions;
    final segments = _listeningSegments;
    if (sessions == null || segments == null) return null;
    try {
      return await AnalyticsArtistListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
        artistAttribution: attribution,
      ).load(period: AnalyticsPeriod.lifetime, referenceLocal: _clock());
    } catch (error, stackTrace) {
      _log('Listening time could not be read', error, stackTrace);
      return null;
    }
  }

  /// Each artist's first Top Track, from the catalogue the profile builds.
  /// Empty when the library has no structured credits to build it from.
  Future<Map<String, ArtistTopTrack>> _topTracks({
    required List<String> artistIds,
    required List<AnalyticsRankedEntity> rankedSongs,
    required ArtistLibraryOrganization? organization,
  }) async {
    final Object library = _library;
    if (library is! SongArtistCreditLinkQueryRepository) return const {};

    final List<SongArtistCreditLink> links;
    final List<LibraryTrack> tracks;
    final Set<String> knownAlbumIds;
    final Map<String, List<String>> ownedAlbumIds;
    try {
      links = await library.getSongArtistCreditLinks();
      tracks = await _library.getTracks();
      final albums = await _library.getAlbums();
      knownAlbumIds = {for (final album in albums) album.albumId};
      ownedAlbumIds = {};
      for (final album in albums) {
        ownedAlbumIds.putIfAbsent(album.artistId, () => []).add(album.albumId);
      }
    } catch (error, stackTrace) {
      _log('Top tracks could not be read', error, stackTrace);
      return const {};
    }

    final trackById = {for (final track in tracks) track.songId: track};
    final tracksByAlbum = <String, List<LibraryTrack>>{};
    for (final track in tracks) {
      tracksByAlbum.putIfAbsent(track.albumId, () => []).add(track);
    }
    final mainSongs = <String, Set<String>>{};
    final featuredSongs = <String, Set<String>>{};
    for (final link in links) {
      if (!trackById.containsKey(link.songId)) continue;
      (link.isMain ? mainSongs : featuredSongs)
          .putIfAbsent(link.artistId, () => <String>{})
          .add(link.songId);
    }

    // Ranking order (streams, latest stream, id), for streamed songs only.
    final songOrder = <String, (int, AnalyticsRankedEntity)>{};
    for (final (index, ranked) in rankedSongs.indexed) {
      if (ranked.qualifiedStreamCount > 0) {
        songOrder[ranked.entityId] = (index, ranked);
      }
    }

    final result = <String, ArtistTopTrack>{};
    for (final artistId in artistIds) {
      final main = mainSongs[artistId] ?? const <String>{};
      final featured = featuredSongs[artistId] ?? const <String>{};
      final contributor =
          organization != null && !organization.isShownInLibrary(artistId);

      // The catalogue, as ArtistProfileController.playbackTracks.
      final Iterable<String> catalogue;
      if (contributor) {
        // A contributor's appearances: its main and featured songs on
        // releases the library knows.
        catalogue = {
          for (final songId in {...main, ...featured})
            if (knownAlbumIds.contains(trackById[songId]!.albumId)) songId,
        };
      } else {
        final own = {...main, ...featured};
        catalogue = {
          ...main,
          for (final albumId in ownedAlbumIds[artistId] ?? const <String>[])
            for (final track in tracksByAlbum[albumId] ?? const [])
              if (track.artistId != artistId && !own.contains(track.songId))
                track.songId,
        };
      }

      (int, AnalyticsRankedEntity)? best;
      for (final songId in catalogue) {
        final order = songOrder[songId];
        if (order == null || trackById[songId]!.isBlocked) continue;
        if (best == null || order.$1 < best.$1) best = order;
      }
      if (best != null) {
        result[artistId] = ArtistTopTrack(
          track: trackById[best.$2.entityId]!,
          streamCount: best.$2.qualifiedStreamCount,
        );
      }
    }
    return result;
  }

  static void _log(String message, Object error, StackTrace stackTrace) {
    developer.log(
      '$message (${error.runtimeType})',
      name: 'sonus.library.artist_statistics',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
