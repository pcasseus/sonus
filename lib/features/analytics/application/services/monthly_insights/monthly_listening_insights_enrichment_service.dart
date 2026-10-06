// ignore_for_file: prefer_initializing_formals

import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../../../library/application/repositories/library_query_repository.dart';
import '../../../domain/entities/playback_session.dart';
import '../../../domain/repositories/playback_session_repository.dart';
import '../../models/monthly_insights/monthly_album_insight_row.dart';
import '../../models/monthly_insights/monthly_artist_insight_row.dart';
import '../../models/monthly_insights/monthly_listening_insights.dart';
import '../../models/monthly_insights/monthly_listening_insights_presentation_data.dart';
import '../../models/monthly_insights/monthly_ranked_entity.dart';
import '../../models/monthly_insights/monthly_track_insight_row.dart';

abstract interface class MonthlyListeningInsightsEnricher {
  Future<MonthlyListeningInsightsPresentationData> enrich(
    MonthlyListeningInsights insights,
  );
}

class MonthlyListeningInsightsEnrichmentService
    implements MonthlyListeningInsightsEnricher {
  const MonthlyListeningInsightsEnrichmentService({
    required LibraryQueryRepository library,
    required PlaybackSessionRepository playbackSessions,
  }) : _library = library,
       _playbackSessions = playbackSessions;

  final LibraryQueryRepository _library;
  final PlaybackSessionRepository _playbackSessions;

  @override
  Future<MonthlyListeningInsightsPresentationData> enrich(
    MonthlyListeningInsights insights,
  ) async {
    final tracksFuture = _library.getTracks();
    final artistsFuture = _library.getArtists();
    final albumsFuture = _library.getAlbums();

    final window = insights.currentSummary.window;

    final sessionsFuture = _playbackSessions.getAll(
      startedAtOrAfter: window.startUtc,
      startedBefore: window.endUtc,
    );

    final tracks = await tracksFuture;
    final artists = await artistsFuture;
    final albums = await albumsFuture;
    final sessions = await sessionsFuture;

    final tracksById = <String, LibraryTrack>{
      for (final track in tracks) track.songId: track,
    };

    final artistsById = <String, LibraryArtist>{
      for (final artist in artists) artist.artistId: artist,
    };

    final albumsById = <String, LibraryAlbum>{
      for (final album in albums) album.albumId: album,
    };

    final snapshots = _SnapshotIndexes.fromSessions(sessions);

    return MonthlyListeningInsightsPresentationData(
      insights: insights,
      tracks: [
        for (final ranking in insights.songs)
          _buildTrackRow(
            ranking: ranking,
            track: tracksById[ranking.entityId],
            snapshot: snapshots.songs[ranking.entityId],
            insights: insights,
          ),
      ],
      artists: [
        for (final ranking in insights.artists)
          _buildArtistRow(
            ranking: ranking,
            artist: artistsById[ranking.entityId],
            snapshot: snapshots.artists[ranking.entityId],
            insights: insights,
          ),
      ],
      albums: [
        for (final ranking in insights.albums)
          _buildAlbumRow(
            ranking: ranking,
            album: albumsById[ranking.entityId],
            snapshot: snapshots.albums[ranking.entityId],
            insights: insights,
          ),
      ],
    );
  }

  MonthlyTrackInsightRow _buildTrackRow({
    required MonthlyRankedEntity ranking,
    required LibraryTrack? track,
    required PlaybackSession? snapshot,
    required MonthlyListeningInsights insights,
  }) {
    return MonthlyTrackInsightRow(
      track: track,
      title: _displayValue(
        track?.title,
        snapshot?.songTitle,
        fallback: 'Unknown Track',
      ),
      artistName: _displayValue(
        track?.artistName,
        snapshot?.artistName,
        fallback: 'Unknown Artist',
      ),
      albumTitle: _displayValue(
        track?.albumTitle,
        snapshot?.albumTitle,
        fallback: 'Unknown Album',
      ),
      ranking: ranking,
      listeningDuration: insights.entityListeningDurations.song(
        ranking.entityId,
      ),
    );
  }

  MonthlyArtistInsightRow _buildArtistRow({
    required MonthlyRankedEntity ranking,
    required LibraryArtist? artist,
    required PlaybackSession? snapshot,
    required MonthlyListeningInsights insights,
  }) {
    return MonthlyArtistInsightRow(
      artist: artist,
      name: _displayValue(
        artist?.name,
        snapshot?.artistName,
        fallback: 'Unknown Artist',
      ),
      ranking: ranking,
      listeningDuration: insights.entityListeningDurations.artist(
        ranking.entityId,
      ),
    );
  }

  MonthlyAlbumInsightRow _buildAlbumRow({
    required MonthlyRankedEntity ranking,
    required LibraryAlbum? album,
    required PlaybackSession? snapshot,
    required MonthlyListeningInsights insights,
  }) {
    return MonthlyAlbumInsightRow(
      album: album,
      title: _displayValue(
        album?.title,
        snapshot?.albumTitle,
        fallback: 'Unknown Album',
      ),
      artistName: _displayValue(
        album?.artistName,
        snapshot?.artistName,
        fallback: 'Unknown Artist',
      ),
      ranking: ranking,
      listeningDuration: insights.entityListeningDurations.album(
        ranking.entityId,
      ),
    );
  }

  String _displayValue(
    String? current,
    String? snapshot, {
    required String fallback,
  }) {
    final normalizedCurrent = current?.trim();

    if (normalizedCurrent != null && normalizedCurrent.isNotEmpty) {
      return current!;
    }

    final normalizedSnapshot = snapshot?.trim();

    if (normalizedSnapshot != null && normalizedSnapshot.isNotEmpty) {
      return snapshot!;
    }

    return fallback;
  }
}

class _SnapshotIndexes {
  const _SnapshotIndexes({
    required this.songs,
    required this.artists,
    required this.albums,
  });

  final Map<String, PlaybackSession> songs;
  final Map<String, PlaybackSession> artists;
  final Map<String, PlaybackSession> albums;

  factory _SnapshotIndexes.fromSessions(List<PlaybackSession> sessions) {
    final songs = <String, PlaybackSession>{};
    final artists = <String, PlaybackSession>{};
    final albums = <String, PlaybackSession>{};

    for (final session in sessions) {
      _rememberLatest(songs, session.songId, session);

      _rememberLatest(artists, session.artistId, session);

      _rememberLatest(albums, session.albumId, session);
    }

    return _SnapshotIndexes(songs: songs, artists: artists, albums: albums);
  }

  static void _rememberLatest(
    Map<String, PlaybackSession> target,
    String entityId,
    PlaybackSession candidate,
  ) {
    final current = target[entityId];

    if (current == null ||
        candidate.startedAt.isAfter(current.startedAt) ||
        (candidate.startedAt == current.startedAt &&
            candidate.id.compareTo(current.id) > 0)) {
      target[entityId] = candidate;
    }
  }
}
