// ignore_for_file: prefer_initializing_formals

import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../../../library/application/repositories/library_query_repository.dart';
import '../../../domain/entities/playback_session.dart';
import '../../../domain/repositories/playback_session_repository.dart';
import '../../models/year_in_sonus/year_in_sonus_album_row.dart';
import '../../models/year_in_sonus/year_in_sonus_artist_row.dart';
import '../../models/year_in_sonus/year_in_sonus_month_row.dart';
import '../../models/year_in_sonus/year_in_sonus_presentation_data.dart';
import '../../models/year_in_sonus/year_in_sonus_recap.dart';
import '../../models/year_in_sonus/year_in_sonus_track_row.dart';

abstract interface class YearInSonusEnricher {
  Future<YearInSonusPresentationData> enrich(YearInSonusRecap recap);
}

class YearInSonusEnrichmentService implements YearInSonusEnricher {
  const YearInSonusEnrichmentService({
    required LibraryQueryRepository library,
    required PlaybackSessionRepository playbackSessions,
  }) : _library = library,
       _playbackSessions = playbackSessions;

  final LibraryQueryRepository _library;
  final PlaybackSessionRepository _playbackSessions;

  @override
  Future<YearInSonusPresentationData> enrich(YearInSonusRecap recap) async {
    final tracksFuture = _library.getTracks();
    final artistsFuture = _library.getArtists();
    final albumsFuture = _library.getAlbums();

    final window = recap.summary.window;

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

    final trackRows = [
      for (final ranking in recap.topTracks)
        _buildTrackRow(
          rankingEntityId: ranking.entityId,
          recap: recap,
          tracksById: tracksById,
          snapshots: snapshots,
        ),
    ];

    final artistRows = [
      for (final ranking in recap.topArtists)
        _buildArtistRow(
          rankingEntityId: ranking.entityId,
          recap: recap,
          artistsById: artistsById,
          snapshots: snapshots,
        ),
    ];

    final albumRows = [
      for (final ranking in recap.topAlbums)
        _buildAlbumRow(
          rankingEntityId: ranking.entityId,
          recap: recap,
          albumsById: albumsById,
          snapshots: snapshots,
        ),
    ];

    final months = [
      for (final month in recap.months)
        YearInSonusMonthRow(
          month: month,
          topSongTitle: _songTitle(
            month.topSongId,
            tracksById: tracksById,
            snapshots: snapshots,
          ),
          topArtistName: _artistName(
            month.topArtistId,
            artistsById: artistsById,
            snapshots: snapshots,
          ),
        ),
    ];

    return YearInSonusPresentationData(
      recap: recap,
      tracks: List.unmodifiable(trackRows),
      artists: List.unmodifiable(artistRows),
      albums: List.unmodifiable(albumRows),
      months: List.unmodifiable(months),
    );
  }

  YearInSonusTrackRow _buildTrackRow({
    required String rankingEntityId,
    required YearInSonusRecap recap,
    required Map<String, LibraryTrack> tracksById,
    required _SnapshotIndexes snapshots,
  }) {
    final ranking = recap.topTracks.firstWhere(
      (entry) => entry.entityId == rankingEntityId,
    );

    final track = tracksById[rankingEntityId];
    final snapshot = snapshots.songs[rankingEntityId];

    return YearInSonusTrackRow(
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
    );
  }

  YearInSonusArtistRow _buildArtistRow({
    required String rankingEntityId,
    required YearInSonusRecap recap,
    required Map<String, LibraryArtist> artistsById,
    required _SnapshotIndexes snapshots,
  }) {
    final ranking = recap.topArtists.firstWhere(
      (entry) => entry.entityId == rankingEntityId,
    );

    final artist = artistsById[rankingEntityId];
    final snapshot = snapshots.artists[rankingEntityId];

    return YearInSonusArtistRow(
      artist: artist,
      name: _displayValue(
        artist?.name,
        snapshot?.artistName,
        fallback: 'Unknown Artist',
      ),
      ranking: ranking,
    );
  }

  YearInSonusAlbumRow _buildAlbumRow({
    required String rankingEntityId,
    required YearInSonusRecap recap,
    required Map<String, LibraryAlbum> albumsById,
    required _SnapshotIndexes snapshots,
  }) {
    final ranking = recap.topAlbums.firstWhere(
      (entry) => entry.entityId == rankingEntityId,
    );

    final album = albumsById[rankingEntityId];
    final snapshot = snapshots.albums[rankingEntityId];

    return YearInSonusAlbumRow(
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
    );
  }

  String? _songTitle(
    String? songId, {
    required Map<String, LibraryTrack> tracksById,
    required _SnapshotIndexes snapshots,
  }) {
    if (songId == null) {
      return null;
    }

    final track = tracksById[songId];
    final snapshot = snapshots.songs[songId];

    return _displayValue(
      track?.title,
      snapshot?.songTitle,
      fallback: 'Unknown Track',
    );
  }

  String? _artistName(
    String? artistId, {
    required Map<String, LibraryArtist> artistsById,
    required _SnapshotIndexes snapshots,
  }) {
    if (artistId == null) {
      return null;
    }

    final artist = artistsById[artistId];
    final snapshot = snapshots.artists[artistId];

    return _displayValue(
      artist?.name,
      snapshot?.artistName,
      fallback: 'Unknown Artist',
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
