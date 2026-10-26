import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_catalog.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_library.dart';

LibraryTrack libraryTrack(
  String id, {
  String? title,
  String artistId = 'artist-1',
  String artistName = 'Madison Beer',
  String albumId = 'album-1',
  String albumTitle = 'locket',
  int trackNumber = 1,
  bool available = true,
  bool blocked = false,
  String? artworkPath,
}) {
  return LibraryTrack(
    songId: id,
    title: title ?? 'Song $id',
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: '$albumId-standard',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: trackNumber,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: available,
    isSongBlocked: blocked,
    filePath: '/music/$id.mp3',
    artworkPath: artworkPath,
  );
}

class FakeBrowseLibrary implements MediaBrowseLibrary {
  List<LibraryTrack> recent = [];
  List<LibraryTrack> added = [];
  List<LibraryTrack> tracks = [];
  List<LibraryArtist> artistList = [];
  List<LibraryAlbum> albumList = [];
  Map<String, List<LibraryTrack>> albumTracksById = {};
  Map<String, List<LibraryTrack>> artistTracksById = {};
  Map<String, List<LibraryAlbum>> albumsByArtistId = {};
  List<MediaBrowsePlaylist> playlistList = [];
  Map<String, List<LibraryTrack>> playlistTracksById = {};
  int recentLimitAsked = 0;

  @override
  Future<List<LibraryTrack>> recentlyPlayedTracks(int limit) async {
    recentLimitAsked = limit;
    return recent;
  }

  @override
  Future<List<LibraryTrack>> recentlyAddedTracks(int limit) async => added;

  @override
  Future<List<LibraryTrack>> allTracks() async => tracks;

  @override
  Future<List<LibraryArtist>> artists() async => artistList;

  @override
  Future<List<LibraryAlbum>> albums() async => albumList;

  @override
  Future<List<LibraryAlbum>> albumsByArtist(String artistId) async =>
      albumsByArtistId[artistId] ?? const [];

  @override
  Future<List<LibraryTrack>> artistTracks(String artistId) async =>
      artistTracksById[artistId] ?? const [];

  @override
  Future<List<LibraryTrack>> albumTracks(String albumId) async =>
      albumTracksById[albumId] ?? const [];

  @override
  Future<List<MediaBrowsePlaylist>> playlists() async => playlistList;

  @override
  Future<List<LibraryTrack>> playlistTracks(String playlistId) async =>
      playlistTracksById[playlistId] ?? const [];
}

LibraryAlbum libraryAlbum(String id, String title, {String? artworkPath}) =>
    LibraryAlbum(
      albumId: id,
      title: title,
      artistId: 'artist-1',
      artistName: 'Madison Beer',
      trackCount: 4,
      dateAdded: DateTime.utc(2026, 10, 1),
      artworkPath: artworkPath,
    );

void main() {
  late FakeBrowseLibrary library;
  late MediaBrowseCatalog catalog;

  setUp(() {
    library = FakeBrowseLibrary();
    catalog = MediaBrowseCatalog(
      library: library,
      artworkUri: (path) =>
          path == null ? null : Uri.parse('content://test/${path.hashCode}'),
    );
  });

  group('root and categories', () {
    test(
      'the root offers four browsable tabs, as Android Auto allows',
      () async {
        final root = await catalog.children(media.AudioService.browsableRootId);

        expect(root.map((item) => item.title), [
          'Recent',
          'Artists',
          'Albums',
          'Library',
        ]);
        expect(root.every((item) => item.playable == false), isTrue);
        expect(root.length, lessThanOrEqualTo(4));
      },
    );

    test('Library holds Playlists, Songs and Recently Added', () async {
      final children = await catalog.children('sonus:library');

      expect(children.map((item) => item.title), [
        'Playlists',
        'Songs',
        'Recently Added',
      ]);
      expect(children.every((item) => item.playable == false), isTrue);
    });

    test('Albums asks the car for a grid', () async {
      final root = await catalog.children(media.AudioService.browsableRootId);
      final albums = root.singleWhere((item) => item.title == 'Albums');

      expect(
        albums.extras?[media.AndroidContentStyle.browsableHintKey],
        media.AndroidContentStyle.gridItemHintValue,
      );
    });

    test('unknown and malformed IDs give empty lists, not errors', () async {
      for (final id in [
        'nope',
        'sonus:',
        'sonus:unknown',
        'sonus:album',
        'sonus:album:',
        'sonus:songs:extra',
        'sonus:album:%E0%A4%A',
      ]) {
        expect(await catalog.children(id), isEmpty, reason: id);
      }
    });
  });

  group('lists keep their real order and only offer playable songs', () {
    test(
      'an album lists its edition order and skips unplayable songs',
      () async {
        library.albumTracksById['album-1'] = [
          libraryTrack('first', trackNumber: 1),
          libraryTrack('gone', trackNumber: 2, available: false),
          libraryTrack('third', trackNumber: 3),
          libraryTrack('blocked', trackNumber: 4, blocked: true),
          libraryTrack('fifth', trackNumber: 5),
        ];

        final items = await catalog.children('sonus:album:album-1');

        expect(items.map((item) => item.title), [
          'Song first',
          'Song third',
          'Song fifth',
        ]);
        expect(items.every((item) => item.playable == true), isTrue);
        expect(items.first.id, 'sonus:album:album-1/song:first');
      },
    );

    test('a playlist keeps its saved order', () async {
      library.playlistList = [
        const MediaBrowsePlaylist(id: 'p1', name: 'Drive', trackCount: 3),
      ];
      library.playlistTracksById['p1'] = [
        libraryTrack('c'),
        libraryTrack('a'),
        libraryTrack('b'),
      ];

      final playlists = await catalog.children('sonus:playlists');
      expect(playlists.single.title, 'Drive');
      expect(playlists.single.displaySubtitle, '3 songs');
      expect(playlists.single.playable, isFalse);

      final songs = await catalog.children(playlists.single.id);
      expect(songs.map((item) => item.title), ['Song c', 'Song a', 'Song b']);
    });

    test('an artist shows albums, then songs, each grouped', () async {
      library.artistList = [
        LibraryArtist(
          artistId: 'artist-1',
          name: 'Madison Beer',
          albumCount: 1,
          songCount: 1,
          dateAdded: DateTime.utc(2026),
          headerArtworkPath: '/banner.jpg',
          topArtistsArtworkPath: '/portrait.jpg',
        ),
      ];
      library.albumsByArtistId['artist-1'] = [
        libraryAlbum('album-1', 'locket'),
      ];
      library.artistTracksById['artist-1'] = [libraryTrack('s1')];

      final artists = await catalog.children('sonus:artists');
      expect(artists.single.title, 'Madison Beer');
      expect(artists.single.displaySubtitle, '1 song');
      // The portrait, not the wide banner, represents the artist.
      expect(
        artists.single.artUri,
        Uri.parse('content://test/${'/portrait.jpg'.hashCode}'),
      );

      final children = await catalog.children(artists.single.id);
      expect(children.map((item) => (item.title, item.playable)), [
        ('locket', false),
        ('Song s1', true),
      ]);
      expect(
        children
            .first
            .extras?['android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT'],
        'Albums',
      );
      expect(
        children
            .last
            .extras?['android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT'],
        'Songs',
      );
      expect(children.last.id, 'sonus:artist-songs:artist-1/song:s1');
    });

    test('recent lists are capped', () async {
      await catalog.children('sonus:recent');
      expect(library.recentLimitAsked, MediaBrowseCatalog.recentLimit);
    });

    test('songs carry title, artist, album, duration and artwork', () async {
      library.tracks = [libraryTrack('a', artworkPath: '/art/a.jpg')];

      final song = (await catalog.children('sonus:songs')).single;

      expect(song.title, 'Song a');
      expect(song.artist, 'Madison Beer');
      expect(song.album, 'locket');
      expect(song.displaySubtitle, 'Madison Beer · locket');
      expect(song.duration, const Duration(minutes: 3));
      expect(song.artUri, Uri.parse('content://test/${'/art/a.jpg'.hashCode}'));
    });

    test('missing artwork gives no artwork, not a broken URI', () async {
      library.tracks = [libraryTrack('a')];

      final song = (await catalog.children('sonus:songs')).single;

      expect(song.artUri, isNull);
    });
  });

  group('media IDs', () {
    test('any library ID round-trips, including separators', () async {
      const awkward = 'album:with/song:and %20 spaces';
      library.albumTracksById[awkward] = [libraryTrack('x/song:y')];

      final container = MediaBrowseContainer.album(awkward);
      final items = await catalog.children(container.mediaId);
      final parsed = MediaBrowsePlayableId.tryParse(items.single.id)!;

      expect(parsed.container, container);
      expect(parsed.songId, 'x/song:y');
    });

    test('the same song in two lists has two distinct IDs', () async {
      library.tracks = [libraryTrack('a')];
      library.albumTracksById['album-1'] = [libraryTrack('a')];

      final fromSongs = (await catalog.children('sonus:songs')).single.id;
      final fromAlbum = (await catalog.children(
        'sonus:album:album-1',
      )).single.id;

      expect(fromSongs, isNot(fromAlbum));
    });

    test('an item is looked up again from its list', () async {
      library.albumTracksById['album-1'] = [libraryTrack('a')];

      final item = await catalog.item('sonus:album:album-1/song:a');
      expect(item?.title, 'Song a');

      expect(await catalog.item('sonus:album:album-1/song:missing'), isNull);
      expect(await catalog.item('sonus:album:album-1'), isNull);
    });
  });

  group('playing from the car keeps the surrounding list', () {
    setUp(() {
      library.albumTracksById['album-1'] = [
        libraryTrack('first'),
        libraryTrack('second'),
        libraryTrack('third'),
        libraryTrack('fourth'),
      ];
    });

    test('tapping the third song queues the whole album from there', () async {
      final queue = await catalog.queueFor('sonus:album:album-1/song:third');

      expect(queue!.tracks.map((t) => t.songId), [
        'first',
        'second',
        'third',
        'fourth',
      ]);
      expect(queue.startIndex, 2);
    });

    test('unplayable songs are left out and the index still matches', () async {
      library.albumTracksById['album-1']!.insert(
        1,
        libraryTrack('missing', available: false),
      );

      final queue = await catalog.queueFor('sonus:album:album-1/song:third');

      expect(queue!.tracks[queue.startIndex].songId, 'third');
      expect(queue.tracks.map((t) => t.songId), isNot(contains('missing')));
    });

    test('a song that became unavailable cannot be played', () async {
      library.albumTracksById['album-1']![2] = libraryTrack(
        'third',
        available: false,
      );

      expect(await catalog.queueFor('sonus:album:album-1/song:third'), isNull);
    });

    test('a removed song cannot be played', () async {
      expect(await catalog.queueFor('sonus:album:album-1/song:gone'), isNull);
    });
  });

  group('search', () {
    setUp(() {
      library.tracks = [
        libraryTrack('1', title: 'angel wings'),
        libraryTrack('2', title: 'Bittersweet'),
        libraryTrack('3', title: 'locket theme'),
        libraryTrack(
          '4',
          title: 'Other',
          artistName: 'Someone Else',
          albumTitle: 'Elsewhere',
        ),
        libraryTrack('5', title: 'Angel', blocked: true),
      ];
    });

    test('matches title, artist and album words, best title first', () async {
      final results = await catalog.search('ANGEL');
      expect(results.map((item) => item.title), ['angel wings']);

      final byArtist = await catalog.search('someone');
      expect(byArtist.map((item) => item.title), ['Other']);

      final byAlbum = await catalog.search('locket');
      // Every Madison Beer song is on "locket"; "locket theme" leads.
      expect(byAlbum.first.title, 'locket theme');
    });

    test('blank searches find nothing', () async {
      expect(await catalog.search('   '), isEmpty);
    });

    test('a search result plays the result list from that song', () async {
      final results = await catalog.search('madison');
      final queue = await catalog.queueFor(results[1].id);

      expect(queue!.tracks.length, results.length);
      expect(queue.startIndex, 1);
    });
  });

  group('voice requests', () {
    setUp(() {
      library.albumList = [libraryAlbum('album-1', 'locket')];
      library.albumTracksById['album-1'] = [
        libraryTrack('first'),
        libraryTrack('second'),
      ];
      library.artistList = [
        LibraryArtist(
          artistId: 'artist-2',
          name: 'Sabrina Carpenter',
          albumCount: 1,
          songCount: 2,
          dateAdded: DateTime.utc(2026),
        ),
      ];
      library.artistTracksById['artist-2'] = [
        libraryTrack('s1', artistId: 'artist-2'),
        libraryTrack('s2', artistId: 'artist-2'),
      ];
      library.tracks = [libraryTrack('t1', title: 'angel wings')];
      library.recent = [libraryTrack('r1'), libraryTrack('r2')];
    });

    test('an empty request resumes recent listening', () async {
      final queue = await catalog.queueForSearch('');
      expect(queue!.tracks.map((t) => t.songId), ['r1', 'r2']);
      expect(queue.startIndex, 0);
    });

    test('an empty request with no history plays the library', () async {
      library.recent = [];
      final queue = await catalog.queueForSearch('');
      expect(queue!.tracks.map((t) => t.songId), ['t1']);
    });

    test('an album name plays the album in order', () async {
      final queue = await catalog.queueForSearch('Locket');
      expect(queue!.tracks.map((t) => t.songId), ['first', 'second']);
    });

    test('an artist name plays the artist', () async {
      final queue = await catalog.queueForSearch('sabrina carpenter');
      expect(queue!.tracks.map((t) => t.songId), ['s1', 's2']);
    });

    test('structured artist extras are honoured', () async {
      final queue = await catalog.queueForSearch(
        '',
        artist: 'Sabrina Carpenter',
      );
      expect(queue!.tracks.first.songId, 's1');
    });

    test('anything else plays matching songs', () async {
      final queue = await catalog.queueForSearch('angel');
      expect(queue!.tracks.single.songId, 't1');
    });

    test('nothing matching plays nothing', () async {
      expect(await catalog.queueForSearch('zzzz'), isNull);
    });
  });
}
