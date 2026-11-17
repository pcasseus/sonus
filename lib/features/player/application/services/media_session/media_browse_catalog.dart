import 'package:audio_service/audio_service.dart' as media;

import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../controllers/playback_coordinator.dart';
import 'media_browse_library.dart';
import 'media_session_state_mapper.dart';
import 'voice_request_resolver.dart';

/// The browsable library that Android Auto and other media browsers see.
///
/// Every list comes from [MediaBrowseLibrary], the same repositories the app
/// reads, and every playable item's media ID names the list it was shown
/// in. Playing an item therefore rebuilds that exact list as the queue, so
/// Previous and Next behave as they do in the app.
///
/// Only playable songs (not blacklisted, with an available file) are
/// offered, using [PlaybackCoordinator.isPlayable], the app's own rule.
class MediaBrowseCatalog {
  MediaBrowseCatalog({required this._library, CarArtworkUri? artworkUri})
    : _artworkUri = artworkUri ?? _noArtwork;

  /// Recently played and recently added lists are capped so a car list
  /// stays short and quick to load.
  static const int recentLimit = 50;

  /// Search results offered per query.
  static const int searchLimit = 50;

  final MediaBrowseLibrary _library;
  final CarArtworkUri _artworkUri;

  /// The four root tabs. Android Auto shows at most four browsable root
  /// items, so Playlists, Songs and Recently Added sit under Library.
  static const List<MediaBrowseCategory> rootTabs = [
    MediaBrowseCategory.recent,
    MediaBrowseCategory.artists,
    MediaBrowseCategory.albums,
    MediaBrowseCategory.library,
  ];

  static const List<MediaBrowseCategory> libraryCategories = [
    MediaBrowseCategory.playlists,
    MediaBrowseCategory.songs,
    MediaBrowseCategory.recentlyAdded,
  ];

  /// The children of [parentMediaId], in display order. Unknown or
  /// vanished parents return an empty list.
  Future<List<media.MediaItem>> children(String parentMediaId) async {
    if (parentMediaId == media.AudioService.browsableRootId) {
      return [for (final tab in rootTabs) _categoryItem(tab)];
    }

    if (parentMediaId == media.AudioService.recentRootId) {
      // The "recent" root asks for the item to resume, if any.
      final recent = await _containerTracks(MediaBrowseContainer.recent);
      return recent.isEmpty
          ? const []
          : [_songItem(MediaBrowseContainer.recent, recent.first)];
    }

    final container = MediaBrowseContainer.tryParse(parentMediaId);

    if (container == null) {
      return const [];
    }

    switch (container.kind) {
      case MediaBrowseContainerKind.library:
        return [for (final c in libraryCategories) _categoryItem(c)];
      case MediaBrowseContainerKind.artists:
        final artists = await _library.artists();
        return [for (final artist in artists) _artistItem(artist)];
      case MediaBrowseContainerKind.albums:
        final albums = await _library.albums();
        return [for (final album in albums) _albumItem(album)];
      case MediaBrowseContainerKind.playlists:
        final playlists = await _library.playlists();
        return [
          for (final playlist in playlists)
            media.MediaItem(
              id: MediaBrowseContainer.playlist(playlist.id).mediaId,
              title: playlist.name,
              displaySubtitle: _songCount(playlist.trackCount),
              playable: false,
            ),
        ];
      case MediaBrowseContainerKind.artist:
        return _artistChildren(container);
      case MediaBrowseContainerKind.recent:
      case MediaBrowseContainerKind.recentlyAdded:
      case MediaBrowseContainerKind.songs:
      case MediaBrowseContainerKind.album:
      case MediaBrowseContainerKind.artistSongs:
      case MediaBrowseContainerKind.playlist:
      case MediaBrowseContainerKind.search:
        final tracks = await _containerTracks(container);
        return [for (final track in tracks) _songItem(container, track)];
    }
  }

  /// The item [mediaId] names, or null when it no longer exists.
  Future<media.MediaItem?> item(String mediaId) async {
    final playable = MediaBrowsePlayableId.tryParse(mediaId);

    if (playable == null) {
      return null;
    }

    final tracks = await _containerTracks(playable.container);
    final index = playable.indexIn(tracks);
    return index == -1 ? null : _songItem(playable.container, tracks[index]);
  }

  /// Songs matching [query] by title, artist or album.
  Future<List<media.MediaItem>> search(String query) async {
    final container = MediaBrowseContainer.search(query);
    final tracks = await _containerTracks(container);
    return [for (final track in tracks) _songItem(container, track)];
  }

  /// The queue for a playable [mediaId]: the whole list it was shown in,
  /// starting at that song. Null when the song is gone or unplayable.
  Future<MediaBrowseQueue?> queueFor(String mediaId) async {
    final playable = MediaBrowsePlayableId.tryParse(mediaId);

    if (playable == null) {
      return null;
    }

    final tracks = await _containerTracks(playable.container);
    final index = playable.indexIn(tracks);
    if (index == -1) return null;

    return MediaBrowseQueue(
      tracks,
      index,
      title: await _containerTitle(playable.container),
    );
  }

  /// The playable song [mediaId] names: a song in a browsed list, or a
  /// queue item, whose ID is the song's own. Null when it is gone or
  /// cannot be played.
  Future<LibraryTrack?> track(String mediaId) async {
    final playable = MediaBrowsePlayableId.tryParse(mediaId);

    if (playable != null) {
      final tracks = await _containerTracks(playable.container);
      final index = playable.indexIn(tracks);
      return index == -1 ? null : tracks[index];
    }

    final tracks = await _containerTracks(MediaBrowseContainer.songs);
    return tracks.where((track) => track.songId == mediaId).firstOrNull;
  }

  /// What to play for a spoken request such as "play locket by Madison
  /// Beer", matched by [VoiceRequestResolver]. Each of its targets is
  /// tried in order and the first with playable songs is played.
  Future<VoiceResolution> resolveVoiceRequest(VoiceRequest request) async {
    final index = request.isEmpty
        ? const VoiceLibraryIndex()
        : await _voiceIndex();
    final plan = VoiceRequestResolver.plan(request, index);

    for (final target in plan) {
      final tracks = await _voiceTargetTracks(target);
      if (tracks.isEmpty) continue;

      final title = _voiceTargetTitle(target, request);
      return target.ambiguous
          ? VoiceAmbiguous(tracks, 0, title)
          : VoiceResolved(tracks, 0, title);
    }

    return VoiceNotFound(
      request.spoken,
      // Nothing in the library can be played, whatever was asked for.
      request.isEmpty || index.tracks.isEmpty
          ? VoiceNotFoundReason.nothingToPlay
          : plan.isEmpty
          ? VoiceNotFoundReason.noMatch
          : VoiceNotFoundReason.nothingPlayable,
    );
  }

  Future<VoiceLibraryIndex> _voiceIndex() async {
    final tracks = await _containerTracks(MediaBrowseContainer.songs);
    final recent = await _library.recentlyPlayedTracks(recentLimit);

    return VoiceLibraryIndex(
      tracks: tracks,
      albums: await _library.albums(),
      artists: await _library.artists(),
      playlists: await _library.playlists(),
      recentSongIds: [for (final track in recent) track.songId],
    );
  }

  /// Songs a genre request queues at most, so a car answers quickly.
  static const int genreLimit = 200;

  Future<List<LibraryTrack>> _voiceTargetTracks(VoiceTarget target) async {
    switch (target) {
      case VoiceSongs(:final tracks):
        return tracks;
      case VoiceAlbum(:final album):
        return _containerTracks(MediaBrowseContainer.album(album.albumId));
      case VoiceArtist(:final artist):
        return _containerTracks(
          MediaBrowseContainer.artistSongs(artist.artistId),
        );
      case VoicePlaylist(:final playlist):
        return _containerTracks(MediaBrowseContainer.playlist(playlist.id));
      case VoiceGenre(:final albums):
        final tracks = <LibraryTrack>[];
        for (final album in albums) {
          if (tracks.length >= genreLimit) break;
          tracks.addAll(
            await _containerTracks(MediaBrowseContainer.album(album.albumId)),
          );
        }
        return tracks.take(genreLimit).toList(growable: false);
      case VoiceRecent():
        return _containerTracks(MediaBrowseContainer.recent);
      case VoiceAllSongs():
        return _containerTracks(MediaBrowseContainer.songs);
    }
  }

  /// The queue title names the real list played: the album, artist,
  /// playlist or genre a request resolved to, whatever words were used.
  /// Only a queue of matching songs is a search, titled "Search: …".
  static String _voiceTargetTitle(VoiceTarget target, VoiceRequest request) =>
      switch (target) {
        VoiceSongs() => MediaBrowseLabels.searchTitle(request.spoken),
        VoiceAlbum(:final album) => album.displayTitle,
        VoiceArtist(:final artist) => artist.name,
        VoicePlaylist(:final playlist) => playlist.name,
        VoiceGenre(:final genre) => genre,
        VoiceRecent() => MediaBrowseLabels.recent,
        VoiceAllSongs() => MediaBrowseLabels.songs,
      };

  /// The name of a browsed list, shown as the queue title.
  Future<String?> _containerTitle(MediaBrowseContainer container) async {
    final id = container.id;
    switch (container.kind) {
      case MediaBrowseContainerKind.recent:
        return MediaBrowseLabels.recent;
      case MediaBrowseContainerKind.recentlyAdded:
        return MediaBrowseLabels.recentlyAdded;
      case MediaBrowseContainerKind.songs:
        return MediaBrowseLabels.songs;
      case MediaBrowseContainerKind.search:
        return MediaBrowseLabels.searchTitle(id!);
      case MediaBrowseContainerKind.album:
        final albums = await _library.albums();
        return albums.where((a) => a.albumId == id).firstOrNull?.displayTitle;
      case MediaBrowseContainerKind.artistSongs:
        final artists = await _library.artists();
        return artists.where((a) => a.artistId == id).firstOrNull?.name;
      case MediaBrowseContainerKind.playlist:
        final playlists = await _library.playlists();
        return playlists.where((p) => p.id == id).firstOrNull?.name;
      case MediaBrowseContainerKind.artists:
      case MediaBrowseContainerKind.albums:
      case MediaBrowseContainerKind.library:
      case MediaBrowseContainerKind.playlists:
      case MediaBrowseContainerKind.artist:
        return null;
    }
  }

  Future<List<media.MediaItem>> _artistChildren(
    MediaBrowseContainer artist,
  ) async {
    final albums = await _library.albumsByArtist(artist.id!);
    final songsContainer = MediaBrowseContainer.artistSongs(artist.id!);
    final songs = await _containerTracks(songsContainer);

    return [
      for (final album in albums)
        _albumItem(album, groupTitle: MediaBrowseLabels.albums),
      for (final song in songs)
        _songItem(songsContainer, song, groupTitle: MediaBrowseLabels.songs),
    ];
  }

  Future<List<LibraryTrack>> _containerTracks(
    MediaBrowseContainer container,
  ) async {
    final List<LibraryTrack> tracks = switch (container.kind) {
      MediaBrowseContainerKind.recent => await _library.recentlyPlayedTracks(
        recentLimit,
      ),
      MediaBrowseContainerKind.recentlyAdded =>
        await _library.recentlyAddedTracks(recentLimit),
      MediaBrowseContainerKind.songs => await _library.allTracks(),
      MediaBrowseContainerKind.album => await _library.albumTracks(
        container.id!,
      ),
      MediaBrowseContainerKind.artistSongs => await _library.artistTracks(
        container.id!,
      ),
      MediaBrowseContainerKind.playlist => await _library.playlistTracks(
        container.id!,
      ),
      MediaBrowseContainerKind.search => _matching(
        await _library.allTracks(),
        container.id!,
      ),
      _ => const <LibraryTrack>[],
    };

    return tracks.where(PlaybackCoordinator.isPlayable).toList(growable: false);
  }

  static List<LibraryTrack> _matching(List<LibraryTrack> tracks, String query) {
    final words = _normalize(
      query,
    ).split(' ').where((word) => word.isNotEmpty).toList(growable: false);

    if (words.isEmpty) {
      return const [];
    }

    final scored = <(LibraryTrack, int)>[];

    for (final track in tracks) {
      final title = _normalize(track.title);
      final haystack =
          '$title ${_normalize(track.artistName)} ${_normalize(track.albumTitle)}';
      if (!words.every(haystack.contains)) continue;
      // Exact and prefix title matches first, then everything else.
      final joined = words.join(' ');
      final score = title == joined
          ? 0
          : title.startsWith(joined)
          ? 1
          : 2;
      scored.add((track, score));
    }

    // A stable sort keeps the library's own order inside each score.
    final indexed = scored.indexed.toList()
      ..sort((a, b) {
        final byScore = a.$2.$2.compareTo(b.$2.$2);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });

    return [for (final entry in indexed.take(searchLimit)) entry.$2.$1];
  }

  static String _normalize(String value) => voiceWords(value).join(' ');

  media.MediaItem _categoryItem(MediaBrowseCategory category) {
    return media.MediaItem(
      id: category.container.mediaId,
      title: category.label,
      playable: false,
      extras: category.gridChildren
          ? const {
              media.AndroidContentStyle.browsableHintKey:
                  media.AndroidContentStyle.gridItemHintValue,
            }
          : null,
    );
  }

  media.MediaItem _artistItem(LibraryArtist artist) {
    return media.MediaItem(
      id: MediaBrowseContainer.artist(artist.artistId).mediaId,
      title: artist.name,
      displaySubtitle: _songCount(artist.songCount),
      artUri: _artworkUri(
        artist.topArtistsArtworkPath ?? artist.headerArtworkPath,
      ),
      playable: false,
    );
  }

  media.MediaItem _albumItem(LibraryAlbum album, {String? groupTitle}) {
    return media.MediaItem(
      id: MediaBrowseContainer.album(album.albumId).mediaId,
      title: album.displayTitle,
      artist: album.artistName,
      displaySubtitle: album.artistName,
      artUri: _artworkUri(album.artworkPath),
      playable: false,
      extras: groupTitle == null ? null : {_groupTitleKey: groupTitle},
    );
  }

  media.MediaItem _songItem(
    MediaBrowseContainer container,
    LibraryTrack track, {
    String? groupTitle,
  }) {
    return media.MediaItem(
      id: MediaBrowsePlayableId(container, track.songId).mediaId,
      title: track.displayTitle,
      artist: track.creditLine,
      // The edition the song is listed on, as Now Playing shows it.
      album: track.editionDisplayTitle,
      displaySubtitle: '${track.creditLine} · ${track.editionDisplayTitle}',
      duration: track.durationSeconds > 0
          ? Duration(seconds: track.durationSeconds)
          : null,
      artUri: _artworkUri(track.artworkPath),
      playable: true,
      extras: groupTitle == null ? null : {_groupTitleKey: groupTitle},
    );
  }

  static String _songCount(int count) => count == 1 ? '1 song' : '$count songs';

  static Uri? _noArtwork(String? _) => null;

  static const String _groupTitleKey =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';
}

/// A list chosen in the car, with the song to start at.
class MediaBrowseQueue {
  const MediaBrowseQueue(this.tracks, this.startIndex, {this.title});

  final List<LibraryTrack> tracks;
  final int startIndex;

  /// The queue title the car shows, when the list has a name.
  final String? title;
}

/// The answer to a voice request (see
/// [MediaBrowseCatalog.resolveVoiceRequest]).
sealed class VoiceResolution {
  const VoiceResolution();
}

/// Songs to play, best match first, with the queue title.
class VoiceResolved extends VoiceResolution implements MediaBrowseQueue {
  const VoiceResolved(this.tracks, this.startIndex, this.title);

  @override
  final List<LibraryTrack> tracks;

  @override
  final int startIndex;

  @override
  final String title;
}

/// Several matches were equally good; [tracks] starts with the one the
/// documented tie-breaks chose (see [VoiceRequestResolver]).
class VoiceAmbiguous extends VoiceResolved {
  const VoiceAmbiguous(super.tracks, super.startIndex, super.title);
}

enum VoiceNotFoundReason {
  /// Nothing in the library can be played (for any request, empty or not).
  nothingToPlay,

  /// Nothing in the library has that name.
  noMatch,

  /// Something matched, but none of its songs can be played (an empty
  /// playlist, or only blocked or unavailable files).
  nothingPlayable,
}

/// Nothing to play; [spoken] is the request in words.
class VoiceNotFound extends VoiceResolution {
  const VoiceNotFound(this.spoken, this.reason);

  final String spoken;
  final VoiceNotFoundReason reason;
}

abstract final class MediaBrowseLabels {
  static const String recent = 'Recent';
  static const String artists = 'Artists';
  static const String albums = 'Albums';
  static const String library = 'Library';
  static const String playlists = 'Playlists';
  static const String songs = 'Songs';
  static const String recentlyAdded = 'Recently Added';

  /// The queue title of search results and spoken song requests.
  static String searchTitle(String query) => 'Search: $query';
}

enum MediaBrowseCategory {
  recent(MediaBrowseLabels.recent, MediaBrowseContainerKind.recent),
  artists(MediaBrowseLabels.artists, MediaBrowseContainerKind.artists),
  albums(MediaBrowseLabels.albums, MediaBrowseContainerKind.albums, true),
  library(MediaBrowseLabels.library, MediaBrowseContainerKind.library),
  playlists(MediaBrowseLabels.playlists, MediaBrowseContainerKind.playlists),
  songs(MediaBrowseLabels.songs, MediaBrowseContainerKind.songs),
  recentlyAdded(
    MediaBrowseLabels.recentlyAdded,
    MediaBrowseContainerKind.recentlyAdded,
  );

  const MediaBrowseCategory(this.label, this.kind, [this.gridChildren = false]);

  final String label;
  final MediaBrowseContainerKind kind;
  final bool gridChildren;

  MediaBrowseContainer get container => MediaBrowseContainer._(kind);
}

enum MediaBrowseContainerKind {
  recent('recent'),
  artists('artists'),
  albums('albums'),
  library('library'),
  playlists('playlists'),
  songs('songs'),
  recentlyAdded('added'),
  artist('artist'),
  artistSongs('artist-songs'),
  album('album'),
  playlist('playlist'),
  search('search');

  const MediaBrowseContainerKind(this.token);

  final String token;

  bool get hasId => switch (this) {
    artist || artistSongs || album || playlist || search => true,
    _ => false,
  };
}

/// A browsable list's stable media ID: `sonus:<kind>` or
/// `sonus:<kind>:<id>`. IDs are URI-encoded, so any library ID round-trips.
class MediaBrowseContainer {
  const MediaBrowseContainer._(this.kind, [this.id]);

  factory MediaBrowseContainer.artist(String id) =>
      MediaBrowseContainer._(MediaBrowseContainerKind.artist, id);

  factory MediaBrowseContainer.artistSongs(String id) =>
      MediaBrowseContainer._(MediaBrowseContainerKind.artistSongs, id);

  factory MediaBrowseContainer.album(String id) =>
      MediaBrowseContainer._(MediaBrowseContainerKind.album, id);

  factory MediaBrowseContainer.playlist(String id) =>
      MediaBrowseContainer._(MediaBrowseContainerKind.playlist, id);

  factory MediaBrowseContainer.search(String query) =>
      MediaBrowseContainer._(MediaBrowseContainerKind.search, query);

  static const MediaBrowseContainer recent = MediaBrowseContainer._(
    MediaBrowseContainerKind.recent,
  );

  static const MediaBrowseContainer songs = MediaBrowseContainer._(
    MediaBrowseContainerKind.songs,
  );

  static const String prefix = 'sonus:';

  final MediaBrowseContainerKind kind;
  final String? id;

  String get mediaId => id == null
      ? '$prefix${kind.token}'
      : '$prefix${kind.token}:${Uri.encodeComponent(id!)}';

  static MediaBrowseContainer? tryParse(String mediaId) {
    if (!mediaId.startsWith(prefix)) return null;

    final body = mediaId.substring(prefix.length);
    final separator = body.indexOf(':');
    final token = separator == -1 ? body : body.substring(0, separator);
    final kind = MediaBrowseContainerKind.values
        .where((candidate) => candidate.token == token)
        .firstOrNull;

    if (kind == null) return null;

    if (!kind.hasId) {
      return separator == -1 ? MediaBrowseContainer._(kind) : null;
    }

    if (separator == -1) return null;

    try {
      final id = Uri.decodeComponent(body.substring(separator + 1));
      return id.isEmpty ? null : MediaBrowseContainer._(kind, id);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaBrowseContainer && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// A playable song's media ID: its list, then `/song:<songId>`.
///
/// A playlist may hold the same song twice; the first occurrence is used,
/// which plays the same audio and keeps the surrounding order.
class MediaBrowsePlayableId {
  const MediaBrowsePlayableId(this.container, this.songId);

  static const String separator = '/song:';

  final MediaBrowseContainer container;
  final String songId;

  String get mediaId =>
      '${container.mediaId}$separator${Uri.encodeComponent(songId)}';

  int indexIn(List<LibraryTrack> tracks) =>
      tracks.indexWhere((track) => track.songId == songId);

  static MediaBrowsePlayableId? tryParse(String mediaId) {
    final at = mediaId.lastIndexOf(separator);
    if (at <= 0) return null;

    final container = MediaBrowseContainer.tryParse(mediaId.substring(0, at));
    if (container == null) return null;

    try {
      final songId = Uri.decodeComponent(
        mediaId.substring(at + separator.length),
      );
      return songId.isEmpty ? null : MediaBrowsePlayableId(container, songId);
    } on ArgumentError {
      return null;
    }
  }
}
