import '../../../../library/application/models/library_album.dart';
import '../../../../library/application/models/library_artist.dart';
import '../../../../library/application/models/library_track.dart';
import '../../../../library/application/models/song_display_title.dart';
import '../../../../library/domain/entities/song.dart';
import 'media_browse_library.dart';

/// Android's keys and values for a structured voice request (MediaStore
/// `EXTRA_MEDIA_*` and the `ENTRY_CONTENT_TYPE` focus values).
abstract final class VoiceRequestKeys {
  static const String focus = 'android.intent.extra.focus';
  static const String title = 'android.intent.extra.title';
  static const String artist = 'android.intent.extra.artist';
  static const String album = 'android.intent.extra.album';
  static const String playlist = 'android.intent.extra.playlist';
  static const String genre = 'android.intent.extra.genre';

  static const String focusAny = 'vnd.android.cursor.item/*';
  static const String focusSong = 'vnd.android.cursor.item/audio';
  static const String focusArtist = 'vnd.android.cursor.item/artist';
  static const String focusAlbum = 'vnd.android.cursor.item/album';
  static const String focusPlaylist = 'vnd.android.cursor.item/playlist';
  static const String focusGenre = 'vnd.android.cursor.item/genre';
}

/// What kind of thing a voice request says it wants.
enum VoiceFocus {
  /// No focus, or `vnd.android.cursor.item/*`: an unstructured request.
  any,
  song,
  artist,
  album,
  playlist,
  genre;

  static VoiceFocus parse(Object? value) => switch (value) {
    VoiceRequestKeys.focusSong => song,
    VoiceRequestKeys.focusArtist => artist,
    VoiceRequestKeys.focusAlbum => album,
    VoiceRequestKeys.focusPlaylist => playlist,
    VoiceRequestKeys.focusGenre => genre,
    _ => any,
  };
}

/// A spoken request as Android Auto or the Assistant sends it: the free
/// query plus whatever structured extras came with it. Absent or non-text
/// extras are empty strings.
class VoiceRequest {
  const VoiceRequest({
    this.query = '',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.playlist = '',
    this.genre = '',
    this.focus = VoiceFocus.any,
  });

  factory VoiceRequest.fromSearch(String query, Map<String, dynamic>? extras) {
    String read(String key) {
      final value = extras?[key];
      return value is String ? value.trim() : '';
    }

    return VoiceRequest(
      query: query.trim(),
      title: read(VoiceRequestKeys.title),
      artist: read(VoiceRequestKeys.artist),
      album: read(VoiceRequestKeys.album),
      playlist: read(VoiceRequestKeys.playlist),
      genre: read(VoiceRequestKeys.genre),
      focus: VoiceFocus.parse(extras?[VoiceRequestKeys.focus]),
    );
  }

  final String query;
  final String title;
  final String artist;
  final String album;
  final String playlist;
  final String genre;
  final VoiceFocus focus;

  /// Nothing named at all, as in "play music on Sonus".
  bool get isEmpty =>
      query.isEmpty &&
      title.isEmpty &&
      artist.isEmpty &&
      album.isEmpty &&
      playlist.isEmpty &&
      genre.isEmpty;

  /// The request in words, for messages and the queue title.
  String get spoken {
    if (query.isNotEmpty) return query;
    if (title.isNotEmpty && artist.isNotEmpty) return '$title by $artist';
    return [
      playlist,
      title,
      album,
      artist,
      genre,
    ].firstWhere((part) => part.isNotEmpty, orElse: () => '');
  }
}

/// The library a voice request is matched against. [tracks] holds only
/// playable songs, in library order; [recentSongIds] is most recent first.
class VoiceLibraryIndex {
  const VoiceLibraryIndex({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.recentSongIds = const [],
  });

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;
  final List<MediaBrowsePlaylist> playlists;
  final List<String> recentSongIds;
}

/// One way to answer a request. The catalog loads each target's songs in
/// order and plays the first that has any.
sealed class VoiceTarget {
  const VoiceTarget({this.ambiguous = false});

  /// More than one candidate was equally good; this one won a tie-break.
  final bool ambiguous;
}

/// Matching songs, best first.
final class VoiceSongs extends VoiceTarget {
  const VoiceSongs(this.tracks, {super.ambiguous});

  final List<LibraryTrack> tracks;
}

final class VoiceAlbum extends VoiceTarget {
  const VoiceAlbum(this.album, {super.ambiguous});

  final LibraryAlbum album;
}

final class VoiceArtist extends VoiceTarget {
  const VoiceArtist(this.artist, {super.ambiguous});

  final LibraryArtist artist;
}

final class VoicePlaylist extends VoiceTarget {
  const VoicePlaylist(this.playlist, {super.ambiguous});

  final MediaBrowsePlaylist playlist;
}

/// Every album filed under [genre], in library order.
final class VoiceGenre extends VoiceTarget {
  const VoiceGenre(this.genre, this.albums);

  final String genre;
  final List<LibraryAlbum> albums;
}

/// Recent listening, most recent first.
final class VoiceRecent extends VoiceTarget {
  const VoiceRecent();
}

/// The whole library, in library order.
final class VoiceAllSongs extends VoiceTarget {
  const VoiceAllSongs();
}

/// Matches a [VoiceRequest] to what Sonus should play. Pure: it reads only
/// the [VoiceLibraryIndex] it is given and always answers the same way.
///
/// ## Rules
///
/// Names are compared by [voiceKey]: case, diacritics ("Beyoncé" =
/// "beyonce"), apostrophes ("Don't" = "dont"), "&" = "and", other
/// punctuation and a leading "the" are ignored.
///
/// * **Empty request**: recent listening, else the whole library.
/// * **Playlist** (playlist extra or playlist focus): only playlists, by
///   name, with a trailing "playlist" and a leading "my" ignored. Same-named
///   playlists are tried in library order; an empty one is skipped, and no
///   playable playlist means not found (never random songs).
/// * **Genre** (genre extra or genre focus): only albums filed under that
///   genre (a trailing "music" ignored).
/// * **Album focus / album extra**: the album, then matching songs.
///   Same-named albums: the one by the artist named, else library order.
/// * **Artist focus / artist extra alone**: the artist, then songs.
/// * **Song focus / title extra**: songs (title extra: then album/artist).
/// * **Free query**: a song whose title is exactly the query first (so an
///   album and a song with the same name play the song), then an album,
///   artist or playlist named exactly, then "`title` by `artist`" (song,
///   then album), then a genre, then songs containing every word of the
///   query.
///
/// ## Song ranking (ties broken in this order)
///
/// 1. **Artist named**: primary artist matches, then credited (co-primary,
///    featured or guest), then any other artist.
/// 2. **Title**: the display title (with its version) is the request, then
///    the stored title is, then the title starts with it, then every word
///    appears in title, artist or album.
/// 3. **Original before versions**: a Remix, Live, Acoustic, Sped Up or
///    other version (see [isVersion]) comes after the original unless the
///    request names that version.
/// 4. **Most recently played** (Sonus's Recent list, the newest 50 songs);
///    Sonus has no play-count signal in the media browser.
/// 5. **Library order**, which is stable.
///
/// A result is ambiguous when its top two songs were only told apart by
/// rules 4 or 5, or several same-named albums, artists or playlists fit.
abstract final class VoiceRequestResolver {
  /// Songs offered per request.
  static const int songLimit = 50;

  /// The targets to try for [request], best first. Empty when nothing in
  /// [index] matches.
  static List<VoiceTarget> plan(VoiceRequest request, VoiceLibraryIndex index) {
    if (request.isEmpty) return const [VoiceRecent(), VoiceAllSongs()];

    final query = request.query;
    final focus = request.focus;
    final playlistName = request.playlist.isNotEmpty
        ? request.playlist
        : focus == VoiceFocus.playlist
        ? query
        : '';

    if (playlistName.isNotEmpty) return _playlists(playlistName, index);

    final genreName = request.genre.isNotEmpty
        ? request.genre
        : focus == VoiceFocus.genre
        ? query
        : '';

    if (genreName.isNotEmpty) return _genre(genreName, index);

    final artist = request.artist;
    final title = request.title.isNotEmpty
        ? request.title
        : focus == VoiceFocus.song
        ? query
        : '';
    final album = request.album.isNotEmpty
        ? request.album
        : focus == VoiceFocus.album
        ? query
        : '';

    if (title.isNotEmpty) {
      return [
        ..._songs(title, artist, index),
        if (focus != VoiceFocus.song) ...[
          ..._albums(album, artist, index),
          ..._artists(artist, index),
        ],
      ];
    }

    if (album.isNotEmpty) {
      return [
        ..._albums(album, artist, index),
        ..._songs(album, artist, index),
      ];
    }

    final artistName = artist.isNotEmpty
        ? artist
        : focus == VoiceFocus.artist
        ? query
        : '';

    if (artistName.isNotEmpty && (query.isEmpty || focus != VoiceFocus.any)) {
      return [
        ..._artists(artistName, index),
        ..._songs(query.isNotEmpty ? query : artistName, '', index),
      ];
    }

    return _freeQuery(query, artist, index);
  }

  static List<VoiceTarget> _freeQuery(
    String query,
    String artist,
    VoiceLibraryIndex index,
  ) {
    final songs = _songs(query, artist, index);
    final exactTitle = _songs(query, artist, index, exactOnly: true).isNotEmpty;
    final byArtist = _splitBy(query);

    return [
      if (exactTitle) ...songs,
      ..._albums(query, artist, index),
      ..._artists(query, index),
      ..._playlists(query, index),
      if (byArtist != null) ...[
        ..._songs(byArtist.$1, byArtist.$2, index, exactOnly: true),
        ..._albums(byArtist.$1, byArtist.$2, index),
      ],
      ..._genre(query, index),
      if (!exactTitle) ...songs,
    ];
  }

  /// "locket by Madison Beer" as ("locket", "Madison Beer").
  static (String, String)? _splitBy(String query) {
    final at = query.toLowerCase().lastIndexOf(' by ');
    if (at <= 0) return null;

    final title = query.substring(0, at).trim();
    final artist = query.substring(at + 4).trim();
    return title.isEmpty || artist.isEmpty ? null : (title, artist);
  }

  static List<VoiceTarget> _songs(
    String phrase,
    String artist,
    VoiceLibraryIndex index, {
    bool exactOnly = false,
  }) {
    final wanted = voiceKey(phrase);
    if (wanted.isEmpty) return const [];

    final words = wanted.split(' ');
    final artistKey = voiceKey(artist);
    final recency = {
      for (final (rank, id) in index.recentSongIds.indexed) id: rank,
    };
    final ranked = <(_SongRank, LibraryTrack)>[];

    for (final (position, track) in index.tracks.indexed) {
      final titleRank = _titleRank(track, wanted, words);
      if (titleRank == null || (exactOnly && titleRank > 1)) continue;

      ranked.add((
        _SongRank(
          artist: _artistRank(track, artistKey),
          title: titleRank,
          version: isVersion(track) && !_namesVersion(track, words) ? 1 : 0,
          recency: recency[track.songId] ?? index.recentSongIds.length,
          position: position,
        ),
        track,
      ));
    }

    if (ranked.isEmpty) return const [];

    ranked.sort((a, b) => a.$1.compareTo(b.$1));
    final ambiguous =
        ranked.length > 1 && ranked[0].$1.sameMatchAs(ranked[1].$1);

    return [
      VoiceSongs([
        for (final entry in ranked.take(songLimit)) entry.$2,
      ], ambiguous: ambiguous),
    ];
  }

  /// 0: display title is the phrase; 1: stored title is; 2: title starts
  /// with it; 3: every word is in title, artist or album; null: no match.
  static int? _titleRank(
    LibraryTrack track,
    String wanted,
    List<String> words,
  ) {
    final display = voiceKey(track.displayTitle);
    if (display == wanted) return 0;

    final stored = voiceKey(track.title);
    if (stored == wanted) return 1;

    if (display.startsWith('$wanted ') || stored.startsWith('$wanted ')) {
      return 2;
    }

    final haystack = [
      display,
      voiceKey(track.creditLine),
      voiceKey(track.albumTitle),
    ].join(' ');
    return words.every(haystack.contains) ? 3 : null;
  }

  /// 0: primary artist is the one named; 1: credited on the song; 2: not
  /// credited. Always 0 when no artist was named.
  static int _artistRank(LibraryTrack track, String artistKey) {
    if (artistKey.isEmpty) return 0;
    if (voiceKey(track.artistName) == artistKey) return 0;

    final credited = [
      ...track.coPrimaryArtists,
      ...track.featuredArtists,
      ...track.guestArtists,
    ].any((name) => voiceKey(name) == artistKey);
    return credited ? 1 : 2;
  }

  /// Whether [track] is a version of a song rather than its original: it
  /// has a version label or characteristic, or its stored title carries a
  /// version word in brackets or after " - ". A remaster alone is the
  /// original recording, so it does not count.
  static bool isVersion(LibraryTrack track) => _versionWords(track).isNotEmpty;

  static Set<String> _versionWords(LibraryTrack track) {
    final words = <String>{
      ...voiceKey(track.versionLabel ?? '').split(' '),
      for (final characteristic in track.versionCharacteristics)
        if (characteristic != SongVersionCharacteristic.remaster)
          ...voiceKey(
            songVersionCharacteristicLabel(characteristic),
          ).split(' '),
    };

    for (final word in voiceWords(track.title)) {
      if (_versionVocabulary.contains(word) &&
          _inQualifier(track.title, word)) {
        words.add(word);
      }
    }

    // A year, as in "Remastered 2011", says nothing about the version.
    return words
      ..remove('')
      ..removeAll(_notVersionWords)
      ..removeWhere((word) => int.tryParse(word) != null);
  }

  /// Whether [word] sits in a bracketed part of [title] or after " - ".
  static bool _inQualifier(String title, String word) {
    final segments = [
      for (final match in RegExp(r'[\(\[]([^\)\]]*)[\)\]]').allMatches(title))
        match.group(1) ?? '',
      if (title.contains(' - ')) title.substring(title.indexOf(' - ') + 3),
    ];
    return segments.any(
      (segment) => voiceKey(segment).split(' ').contains(word),
    );
  }

  static bool _namesVersion(LibraryTrack track, List<String> words) {
    final version = _versionWords(track);
    return words.any(version.contains);
  }

  /// Words that mark a version in a stored title, as in "Song (Sped Up)".
  static const Set<String> _versionVocabulary = {
    'remix',
    'mix',
    'live',
    'acoustic',
    'sped',
    'slowed',
    'reverb',
    'instrumental',
    'demo',
    'edit',
    'extended',
    'version',
    'karaoke',
    'nightcore',
    'unplugged',
    'rework',
    'acapella',
    'cappella',
    'alternate',
    'cover',
  };

  /// Remastering keeps the original recording.
  static const Set<String> _notVersionWords = {'remaster', 'remastered'};

  static List<VoiceTarget> _albums(
    String name,
    String artist,
    VoiceLibraryIndex index,
  ) {
    final wanted = voiceKey(name);
    if (wanted.isEmpty) return const [];

    final artistKey = voiceKey(artist);
    final matches = index.albums
        .where(
          (album) =>
              voiceKey(album.title) == wanted ||
              voiceKey(album.displayTitle) == wanted,
        )
        .toList();
    if (artistKey.isNotEmpty) {
      // A stable sort: the named artist's albums first, library order kept.
      final byArtist = matches
          .where((album) => voiceKey(album.artistName) == artistKey)
          .toList();
      matches
        ..removeWhere(byArtist.contains)
        ..insertAll(0, byArtist);
    }

    final ambiguous =
        matches.length > 1 &&
        (artistKey.isEmpty ||
            voiceKey(matches[1].artistName) == voiceKey(matches[0].artistName));
    return [
      for (final (i, album) in matches.indexed)
        VoiceAlbum(album, ambiguous: i == 0 && ambiguous),
    ];
  }

  static List<VoiceTarget> _artists(String name, VoiceLibraryIndex index) {
    final wanted = voiceKey(name);
    if (wanted.isEmpty) return const [];

    final matches = index.artists
        .where((artist) => voiceKey(artist.name) == wanted)
        .toList();
    return [
      for (final (i, artist) in matches.indexed)
        VoiceArtist(artist, ambiguous: i == 0 && matches.length > 1),
    ];
  }

  static List<VoiceTarget> _playlists(String name, VoiceLibraryIndex index) {
    final wanted = _playlistKey(name);
    if (wanted.isEmpty) return const [];

    final matches = index.playlists
        .where((playlist) => _playlistKey(playlist.name) == wanted)
        .toList();
    return [
      for (final (i, playlist) in matches.indexed)
        VoicePlaylist(playlist, ambiguous: i == 0 && matches.length > 1),
    ];
  }

  /// A playlist name without a leading "my" or a trailing "playlist", so
  /// "my Road Trip playlist" finds "Road Trip".
  static String _playlistKey(String name) {
    var key = voiceKey(name);
    if (key.startsWith('my ')) key = key.substring(3);
    if (key.endsWith(' playlist')) {
      key = key.substring(0, key.length - ' playlist'.length);
    }
    return key.trim();
  }

  static List<VoiceTarget> _genre(String name, VoiceLibraryIndex index) {
    var wanted = voiceKey(name);
    if (wanted.endsWith(' music')) {
      wanted = wanted.substring(0, wanted.length - ' music'.length);
    }
    if (wanted.isEmpty) return const [];

    final albums = index.albums
        .where((album) => voiceKey(album.genre ?? '') == wanted)
        .toList(growable: false);
    return albums.isEmpty
        ? const []
        : [VoiceGenre(albums.first.genre!, albums)];
  }
}

/// A song's place in [VoiceRequestResolver]'s ranking; lower is better.
class _SongRank implements Comparable<_SongRank> {
  const _SongRank({
    required this.artist,
    required this.title,
    required this.version,
    required this.recency,
    required this.position,
  });

  final int artist;
  final int title;
  final int version;
  final int recency;
  final int position;

  /// Equally good apart from the recency and library-order tie-breaks.
  bool sameMatchAs(_SongRank other) =>
      other.artist == artist &&
      other.title == title &&
      other.version == version;

  @override
  int compareTo(_SongRank other) {
    for (final (a, b) in [
      (artist, other.artist),
      (title, other.title),
      (version, other.version),
      (recency, other.recency),
      (position, other.position),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }
}

/// [value] as voice requests compare it: lower case, without diacritics,
/// apostrophes, punctuation or a leading "the", with "&" as "and" and
/// single spaces between words.
String voiceKey(String value) {
  final words = voiceWords(value);
  if (words.length > 1 && words.first == 'the') words.removeAt(0);
  return words.join(' ');
}

/// The words of [value], folded as [voiceKey] folds them, keeping "the".
List<String> voiceWords(String value) {
  final folded = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    // Combining marks, for text that arrives already decomposed.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final char = String.fromCharCode(rune);
    folded.write(_folds[char] ?? char);
  }

  return folded
      .toString()
      .replaceAll(RegExp("['’ʼ`]"), '')
      .replaceAll('&', ' and ')
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Latin letters with diacritics, folded to plain letters. Dart has no
/// Unicode normalization built in; this covers Latin-1 and Latin
/// Extended-A, which is what artist and song names use in practice.
final Map<String, String> _folds = {
  for (final (plain, accented) in const [
    ('a', 'àáâãäåāăą'),
    ('c', 'çćĉċč'),
    ('d', 'ďđð'),
    ('e', 'èéêëēĕėęě'),
    ('g', 'ĝğġģ'),
    ('h', 'ĥħ'),
    ('i', 'ìíîïĩīĭįı'),
    ('j', 'ĵ'),
    ('k', 'ķ'),
    ('l', 'ĺļľŀł'),
    ('n', 'ñńņňŉ'),
    ('o', 'òóôõöøōŏő'),
    ('r', 'ŕŗř'),
    ('s', 'śŝşš'),
    ('t', 'ţťŧ'),
    ('u', 'ùúûüũūŭůűų'),
    ('w', 'ŵ'),
    ('y', 'ýÿŷ'),
    ('z', 'źżž'),
  ])
    for (final char in accented.split('')) char: plain,
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'þ': 'th',
};
