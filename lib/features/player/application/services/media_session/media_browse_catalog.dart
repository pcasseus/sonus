import 'package:audio_service/audio_service.dart' as media;

import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../controllers/playback_coordinator.dart';
import 'media_browse_library.dart';
import 'media_session_state_mapper.dart';

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
    return index == -1 ? null : MediaBrowseQueue(tracks, index);
  }

  /// The queue for a spoken request such as "play Sonus" or "play locket
  /// by Madison Beer". An empty query resumes recent listening. An artist
  /// or album named exactly plays that catalog; otherwise matching songs.
  Future<MediaBrowseQueue?> queueForSearch(
    String query, {
    String? artist,
    String? album,
  }) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty && (artist ?? '').isEmpty && (album ?? '').isEmpty) {
      final recent = await _containerTracks(MediaBrowseContainer.recent);
      final queue = recent.isNotEmpty
          ? recent
          : await _containerTracks(MediaBrowseContainer.songs);
      return queue.isEmpty ? null : MediaBrowseQueue(queue, 0);
    }

    final albumName = _normalize(album ?? '');
    if (albumName.isNotEmpty || trimmed.isNotEmpty) {
      final albums = await _library.albums();
      final wanted = albumName.isNotEmpty ? albumName : _normalize(trimmed);
      final match = albums.where((a) => _normalize(a.title) == wanted);
      if (match.isNotEmpty) {
        final tracks = await _containerTracks(
          MediaBrowseContainer.album(match.first.albumId),
        );
        if (tracks.isNotEmpty) return MediaBrowseQueue(tracks, 0);
      }
    }

    final artistName = _normalize(artist ?? '');
    if (artistName.isNotEmpty || trimmed.isNotEmpty) {
      final artists = await _library.artists();
      final wanted = artistName.isNotEmpty ? artistName : _normalize(trimmed);
      final match = artists.where((a) => _normalize(a.name) == wanted);
      if (match.isNotEmpty) {
        final tracks = await _containerTracks(
          MediaBrowseContainer.artistSongs(match.first.artistId),
        );
        if (tracks.isNotEmpty) return MediaBrowseQueue(tracks, 0);
      }
    }

    final words = [
      trimmed,
      artist ?? '',
      album ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final results = await _containerTracks(MediaBrowseContainer.search(words));
    return results.isEmpty ? null : MediaBrowseQueue(results, 0);
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

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

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
      title: album.title,
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
      title: track.title,
      artist: track.artistName,
      album: track.albumTitle,
      displaySubtitle: '${track.artistName} · ${track.albumTitle}',
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
  const MediaBrowseQueue(this.tracks, this.startIndex);

  final List<LibraryTrack> tracks;
  final int startIndex;
}

abstract final class MediaBrowseLabels {
  static const String recent = 'Recent';
  static const String artists = 'Artists';
  static const String albums = 'Albums';
  static const String library = 'Library';
  static const String playlists = 'Playlists';
  static const String songs = 'Songs';
  static const String recentlyAdded = 'Recently Added';
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
