import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_browse_library.dart';
import 'package:sonus_next/features/player/application/services/media_session/voice_request_resolver.dart';

LibraryTrack song(
  String id,
  String title, {
  String artist = 'Madison Beer',
  String album = 'locket',
  String? versionLabel,
  List<SongVersionCharacteristic> characteristics = const [],
  List<String> featured = const [],
}) {
  return LibraryTrack(
    songId: id,
    title: title,
    artistId: 'id-$artist',
    artistName: artist,
    albumId: 'album-$album',
    albumTitle: album,
    albumEditionId: 'edition-$album',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featured,
    versionLabel: versionLabel,
    versionCharacteristics: characteristics,
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: true,
    filePath: '/music/$id.mp3',
  );
}

LibraryAlbum album(String id, String title, {String artist = 'Madison Beer'}) =>
    LibraryAlbum(
      albumId: id,
      title: title,
      artistId: 'id-$artist',
      artistName: artist,
      trackCount: 1,
      dateAdded: DateTime.utc(2026, 10, 1),
    );

LibraryArtist artist(String id, String name) => LibraryArtist(
  artistId: id,
  name: name,
  albumCount: 1,
  songCount: 1,
  dateAdded: DateTime.utc(2026, 10, 1),
);

List<VoiceTarget> plan(VoiceRequest request, VoiceLibraryIndex index) =>
    VoiceRequestResolver.plan(request, index);

/// The song IDs of the first target, which must be songs.
List<String> songIds(List<VoiceTarget> targets) => [
  for (final track in (targets.first as VoiceSongs).tracks) track.songId,
];

void main() {
  group('requests from Android', () {
    test('extras and focus are read; other types are ignored', () {
      final request = VoiceRequest.fromSearch(' play it ', {
        VoiceRequestKeys.title: 'Angel',
        VoiceRequestKeys.artist: 'Madison Beer',
        VoiceRequestKeys.album: 42,
        VoiceRequestKeys.playlist: 'Gym',
        VoiceRequestKeys.genre: 'Pop',
        VoiceRequestKeys.focus: VoiceRequestKeys.focusPlaylist,
      });

      expect(request.query, 'play it');
      expect(request.title, 'Angel');
      expect(request.artist, 'Madison Beer');
      expect(request.album, '');
      expect(request.playlist, 'Gym');
      expect(request.genre, 'Pop');
      expect(request.focus, VoiceFocus.playlist);
    });

    test('every focus value maps; unknown ones are unstructured', () {
      expect(VoiceFocus.parse(VoiceRequestKeys.focusSong), VoiceFocus.song);
      expect(VoiceFocus.parse(VoiceRequestKeys.focusArtist), VoiceFocus.artist);
      expect(VoiceFocus.parse(VoiceRequestKeys.focusAlbum), VoiceFocus.album);
      expect(VoiceFocus.parse(VoiceRequestKeys.focusGenre), VoiceFocus.genre);
      expect(VoiceFocus.parse(VoiceRequestKeys.focusAny), VoiceFocus.any);
      expect(VoiceFocus.parse(null), VoiceFocus.any);
    });

    test('the request is put in words for messages', () {
      expect(const VoiceRequest(query: 'locket').spoken, 'locket');
      expect(
        const VoiceRequest(title: 'Angel', artist: 'Madison Beer').spoken,
        'Angel by Madison Beer',
      );
      expect(const VoiceRequest(playlist: 'Gym').spoken, 'Gym');
      expect(const VoiceRequest().spoken, '');
    });
  });

  group('names are compared loosely', () {
    test('case, diacritics, apostrophes, & and punctuation', () {
      expect(voiceKey('Beyoncé'), voiceKey('beyonce'));
      expect(voiceKey('Sigur Rós – Ágætis byrjun'), 'sigur ros agaetis byrjun');
      expect(voiceKey("Don't Start Now"), voiceKey('Dont start now'));
      expect(voiceKey('Don’t'), 'dont');
      expect(voiceKey('Simon & Garfunkel'), 'simon and garfunkel');
      expect(voiceKey('  HELLO!!!  world?? '), 'hello world');
      expect(voiceKey('Straße'), 'strasse');
      // Already decomposed input: "e" followed by a combining acute.
      expect(voiceKey('Beyoncé'), 'beyonce');
    });

    test('a leading "the" is ignored, unless it is the whole name', () {
      expect(voiceKey('The Weeknd'), voiceKey('weeknd'));
      expect(voiceKey('The'), 'the');
    });

    test('a song title with diacritics and punctuation is found', () {
      final index = VoiceLibraryIndex(
        tracks: [song('1', 'Café (Interlude)'), song('2', 'Other')],
      );

      expect(
        songIds(plan(const VoiceRequest(query: 'cafe interlude'), index)),
        ['1'],
      );
    });
  });

  group('empty requests', () {
    test('play recent listening, then the library', () {
      final targets = plan(const VoiceRequest(), const VoiceLibraryIndex());

      expect(targets, hasLength(2));
      expect(targets[0], isA<VoiceRecent>());
      expect(targets[1], isA<VoiceAllSongs>());
    });

    test('a bare unstructured focus is still empty', () {
      final request = VoiceRequest.fromSearch('', {
        VoiceRequestKeys.focus: VoiceRequestKeys.focusAny,
      });

      expect(request.isEmpty, isTrue);
      expect(
        plan(request, const VoiceLibraryIndex()).first,
        isA<VoiceRecent>(),
      );
    });
  });

  group('same title by different artists', () {
    final index = VoiceLibraryIndex(
      tracks: [
        song('a1', 'Angel', artist: 'Artist One'),
        song('a2', 'Angel', artist: 'Artist Two'),
        song('a3', 'Angel', artist: 'Artist Three', featured: ['Artist Two']),
      ],
    );

    test('the artist named wins, primary before featured', () {
      final targets = plan(
        const VoiceRequest(title: 'Angel', artist: 'Artist Two'),
        index,
      );

      expect(songIds(targets), ['a2', 'a3', 'a1']);
      expect(targets.first.ambiguous, isFalse);
    });

    test('"title by artist" in the query is understood', () {
      final targets = plan(
        const VoiceRequest(query: 'angel by artist two'),
        index,
      );

      expect(songIds(targets).first, 'a2');
    });

    test('with no artist named, the most recently played wins', () {
      final recent = VoiceLibraryIndex(
        tracks: index.tracks,
        recentSongIds: const ['other', 'a3', 'a2'],
      );

      final targets = plan(const VoiceRequest(query: 'Angel'), recent);
      expect(songIds(targets), ['a3', 'a2', 'a1']);
      expect(targets.first.ambiguous, isTrue);
    });

    test('with no history, library order decides, stably', () {
      final targets = plan(const VoiceRequest(query: 'Angel'), index);

      expect(songIds(targets), ['a1', 'a2', 'a3']);
      expect(targets.first.ambiguous, isTrue);
    });
  });

  group('versions', () {
    final index = VoiceLibraryIndex(
      tracks: [
        song('remix', 'Reckless', versionLabel: 'Remix'),
        song(
          'live',
          'Reckless',
          characteristics: const [SongVersionCharacteristic.live],
        ),
        song('sped', 'Reckless (Sped Up)'),
        song('original', 'Reckless'),
        song(
          'remaster',
          'Selfish',
          characteristics: const [SongVersionCharacteristic.remaster],
        ),
      ],
    );

    test('the original comes before Remix, Live and Sped Up versions', () {
      final ids = songIds(plan(const VoiceRequest(query: 'reckless'), index));

      expect(ids.first, 'original');
      expect(ids.toSet(), {'original', 'remix', 'live', 'sped'});
    });

    test('a named version is played', () {
      expect(
        songIds(plan(const VoiceRequest(query: 'Reckless remix'), index)).first,
        'remix',
      );
      expect(
        songIds(
          plan(const VoiceRequest(title: 'Reckless (Live)'), index),
        ).first,
        'live',
      );
      expect(
        songIds(
          plan(const VoiceRequest(query: 'reckless sped up'), index),
        ).first,
        'sped',
      );
    });

    test('a version named loosely is not ranked below the original', () {
      // Both match every word only; the request names "live", so the
      // version loses its penalty and library order decides.
      final loose = VoiceLibraryIndex(
        tracks: [
          song('live', 'Reckless Tour', versionLabel: 'Live at Wembley'),
          song('original', 'Reckless Tour', album: 'Live Tour'),
        ],
      );

      expect(songIds(plan(const VoiceRequest(query: 'reckless live'), loose)), [
        'live',
        'original',
      ]);
      expect(
        songIds(plan(const VoiceRequest(query: 'reckless tour'), loose)).first,
        'original',
      );
    });

    test('version detection follows Sonus labels; a remaster is original', () {
      expect(VoiceRequestResolver.isVersion(index.tracks[0]), isTrue);
      expect(VoiceRequestResolver.isVersion(index.tracks[1]), isTrue);
      expect(VoiceRequestResolver.isVersion(index.tracks[2]), isTrue);
      expect(VoiceRequestResolver.isVersion(index.tracks[3]), isFalse);
      expect(VoiceRequestResolver.isVersion(index.tracks[4]), isFalse);
      expect(
        VoiceRequestResolver.isVersion(
          song('r', 'Song', versionLabel: 'Remastered 2011'),
        ),
        isFalse,
      );
      expect(
        VoiceRequestResolver.isVersion(song('l', 'Live Forever')),
        isFalse,
        reason: 'a version word outside brackets is part of the title',
      );
    });

    test('original before version also holds among prefix matches', () {
      final prefix = VoiceLibraryIndex(
        tracks: [
          song('v', 'Golden Hour', versionLabel: 'Acoustic'),
          song('o', 'Golden Hour'),
        ],
      );

      expect(songIds(plan(const VoiceRequest(query: 'golden'), prefix)), [
        'o',
        'v',
      ]);
    });
  });

  group('album and song with the same name', () {
    final index = VoiceLibraryIndex(
      tracks: [song('s', 'Locket'), song('x', 'Other')],
      albums: [album('al', 'locket')],
    );

    test('an unstructured request plays the song', () {
      final targets = plan(const VoiceRequest(query: 'locket'), index);

      expect(targets.first, isA<VoiceSongs>());
      expect(targets[1], isA<VoiceAlbum>());
    });

    test('album focus plays the album', () {
      final targets = plan(
        const VoiceRequest(query: 'locket', focus: VoiceFocus.album),
        index,
      );

      expect((targets.first as VoiceAlbum).album.albumId, 'al');
    });

    test('an album extra plays the album', () {
      final targets = plan(const VoiceRequest(album: 'Locket'), index);
      expect(targets.first, isA<VoiceAlbum>());
    });

    test('song focus plays only songs', () {
      final targets = plan(
        const VoiceRequest(query: 'locket', focus: VoiceFocus.song),
        index,
      );

      expect(targets.every((target) => target is VoiceSongs), isTrue);
    });

    test('without a song of that name, the album plays', () {
      final targets = plan(
        const VoiceRequest(query: 'locket'),
        VoiceLibraryIndex(albums: index.albums, tracks: [song('x', 'Other')]),
      );

      expect(targets.first, isA<VoiceAlbum>());
    });

    test('same-named albums: the artist named, else library order', () {
      final albums = VoiceLibraryIndex(
        albums: [
          album('a1', 'Greatest Hits', artist: 'One'),
          album('a2', 'Greatest Hits', artist: 'Two'),
        ],
      );

      final named = plan(
        const VoiceRequest(album: 'greatest hits', artist: 'two'),
        albums,
      );
      expect((named.first as VoiceAlbum).album.albumId, 'a2');
      expect(named.first.ambiguous, isFalse);

      final unnamed = plan(const VoiceRequest(album: 'greatest hits'), albums);
      expect((unnamed.first as VoiceAlbum).album.albumId, 'a1');
      expect(unnamed.first.ambiguous, isTrue);
    });
  });

  group('artists', () {
    final index = VoiceLibraryIndex(
      artists: [artist('w', 'The Weeknd')],
      tracks: [song('1', 'Blinding Lights', artist: 'The Weeknd')],
    );

    test('artist focus plays the artist, then songs', () {
      final targets = plan(
        const VoiceRequest(query: 'weeknd', focus: VoiceFocus.artist),
        index,
      );

      expect((targets.first as VoiceArtist).artist.artistId, 'w');
      expect(targets[1], isA<VoiceSongs>());
    });

    test('an artist extra alone plays the artist', () {
      final targets = plan(const VoiceRequest(artist: 'the weeknd'), index);
      expect(targets.first, isA<VoiceArtist>());
    });
  });

  group('playlists', () {
    final index = VoiceLibraryIndex(
      playlists: const [
        MediaBrowsePlaylist(id: 'p1', name: 'Road Trip!', trackCount: 3),
        MediaBrowsePlaylist(id: 'p2', name: 'road trip', trackCount: 1),
        MediaBrowsePlaylist(id: 'p3', name: 'Gym', trackCount: 1),
      ],
      tracks: [song('1', 'Road Trip')],
    );

    test('the playlist extra is honoured, same names in library order', () {
      final targets = plan(const VoiceRequest(playlist: 'Road trip'), index);

      expect(
        [for (final t in targets) (t as VoicePlaylist).playlist.id],
        ['p1', 'p2'],
      );
      expect(targets.first.ambiguous, isTrue);
    });

    test('playlist focus reads the query, without "my" and "playlist"', () {
      final targets = plan(
        const VoiceRequest(
          query: 'my road trip playlist',
          focus: VoiceFocus.playlist,
        ),
        index,
      );

      expect((targets.first as VoicePlaylist).playlist.id, 'p1');
    });

    test('a playlist request never falls back to songs', () {
      final targets = plan(const VoiceRequest(playlist: 'Nope'), index);
      expect(targets, isEmpty);
    });

    test('an unstructured "… playlist" request finds the playlist', () {
      final targets = plan(const VoiceRequest(query: 'gym playlist'), index);
      expect((targets.first as VoicePlaylist).playlist.id, 'p3');
    });
  });

  test('a genre request offers only albums of that genre', () {
    final index = VoiceLibraryIndex(
      albums: [
        LibraryAlbum(
          albumId: 'j',
          title: 'Blue',
          artistId: 'a',
          artistName: 'A',
          trackCount: 1,
          dateAdded: DateTime.utc(2026),
          genre: 'Jazz',
        ),
      ],
    );

    final targets = plan(
      const VoiceRequest(query: 'jazz', focus: VoiceFocus.genre),
      index,
    );
    expect((targets.single as VoiceGenre).albums.single.albumId, 'j');
    expect(plan(const VoiceRequest(genre: 'rock'), index), isEmpty);
  });

  test('nothing matching gives no targets', () {
    final index = VoiceLibraryIndex(tracks: [song('1', 'Angel')]);

    expect(plan(const VoiceRequest(query: 'zzzz'), index), isEmpty);
    expect(plan(const VoiceRequest(title: 'zzzz'), index), isEmpty);
  });

  test('songs matching by word follow exact and prefix titles', () {
    final index = VoiceLibraryIndex(
      tracks: [
        song('word', 'Wings of an Angel'),
        song('prefix', 'Angel Wings'),
        song('exact', 'Angel'),
      ],
    );

    expect(songIds(plan(const VoiceRequest(query: 'angel'), index)), [
      'exact',
      'prefix',
      'word',
    ]);
  });

  group('explicitly requested versions win over the original', () {
    // The original is listed last, so library order never helps it.
    final index = VoiceLibraryIndex(
      tracks: [
        song('tv', "Love Story (Taylor's Version)"),
        song(
          'radio',
          'Love Story',
          characteristics: const [SongVersionCharacteristic.radioEdit],
        ),
        song('live', 'Love Story', versionLabel: 'Live'),
        song('remix', 'Love Story', versionLabel: 'Remix'),
        song(
          'acoustic',
          'Love Story',
          characteristics: const [SongVersionCharacteristic.acoustic],
        ),
        song('sped', 'Love Story (Sped Up)'),
        song('original', 'Love Story'),
      ],
    );

    const asked = {
      'tv': "Taylor's Version",
      'radio': 'Radio Edit',
      'live': 'Live',
      'remix': 'Remix',
      'acoustic': 'Acoustic',
      'sped': 'Sped Up',
    };

    for (final MapEntry(key: id, value: label) in asked.entries) {
      test('"$label" in the query plays that version', () {
        final targets = plan(VoiceRequest(query: 'love story $label'), index);
        expect(songIds(targets).first, id);
        expect(targets.first.ambiguous, isFalse);
      });

      test('"$label" wins even when the title extra leaves it out', () {
        // The title extra alone matches the original best; the query says
        // which version was asked for.
        final targets = plan(
          VoiceRequest(title: 'Love Story', query: 'love story $label'),
          index,
        );
        expect(songIds(targets).first, id);
      });
    }

    test('"version of" phrasing is understood', () {
      expect(
        songIds(
          plan(const VoiceRequest(query: 'radio edit of love story'), index),
        ).first,
        'radio',
      );
      expect(
        songIds(
          plan(
            const VoiceRequest(query: 'the acoustic version of love story'),
            index,
          ),
        ).first,
        'acoustic',
      );
    });

    test('with no version named, the original plays', () {
      expect(
        songIds(plan(const VoiceRequest(query: 'love story'), index)).first,
        'original',
      );
      expect(
        songIds(plan(const VoiceRequest(title: 'Love Story'), index)).first,
        'original',
      );
    });

    test('with no original in the library, a version plays', () {
      final versionsOnly = VoiceLibraryIndex(
        tracks: [index.tracks[2], index.tracks[0]],
      );

      final ids = songIds(
        plan(const VoiceRequest(query: 'love story'), versionsOnly),
      );
      expect(ids, ['live', 'tv']);
    });

    test('a version word the title already has is not a request', () {
      final live = VoiceLibraryIndex(
        tracks: [song('lv', 'Live Forever (Live)'), song('o', 'Live Forever')],
      );

      expect(
        songIds(
          plan(
            const VoiceRequest(title: 'Live Forever', query: 'live forever'),
            live,
          ),
        ).first,
        'o',
      );
      expect(
        songIds(
          plan(const VoiceRequest(query: 'live forever live'), live),
        ).first,
        'lv',
      );
    });

    test('a version asked for beats an original matching only by album', () {
      final loose = VoiceLibraryIndex(
        tracks: [
          song('original', 'Reckless Tour', album: 'Live Tour'),
          song('live', 'Reckless Tour', versionLabel: 'Live'),
        ],
      );

      expect(
        songIds(
          plan(
            const VoiceRequest(
              title: 'Reckless Tour',
              query: 'reckless tour live',
            ),
            loose,
          ),
        ).first,
        'live',
      );
    });

    test('asking for a version needs its whole title and a version word', () {
      final tv = index.tracks[0];
      List<String> words(String phrase) => voiceKey(phrase).split(' ');

      expect(
        VoiceRequestResolver.asksForVersion(
          tv,
          words("love story taylor's version"),
        ),
        isTrue,
      );
      expect(
        VoiceRequestResolver.asksForVersion(tv, words('love story')),
        isFalse,
      );
      expect(
        VoiceRequestResolver.asksForVersion(tv, words('story taylors version')),
        isFalse,
      );
      expect(
        VoiceRequestResolver.asksForVersion(
          tv,
          words('love story live version'),
        ),
        isFalse,
      );
      expect(
        VoiceRequestResolver.asksForVersion(
          index.tracks.last,
          words('love story live'),
        ),
        isFalse,
        reason: 'the original is not a version',
      );
    });
  });

  group('same title by different artists, title extra', () {
    final index = VoiceLibraryIndex(
      tracks: [
        song('a1', 'Angel', artist: 'Artist One'),
        song('a2', 'Angel', artist: 'Artist Two'),
      ],
    );

    test('without the artist: ambiguous, library order', () {
      final targets = plan(const VoiceRequest(title: 'Angel'), index);
      expect(songIds(targets), ['a1', 'a2']);
      expect(targets.first.ambiguous, isTrue);
    });

    test('with the artist: that artist, not ambiguous', () {
      final targets = plan(
        const VoiceRequest(title: 'Angel', artist: 'artist one'),
        index,
      );
      expect(songIds(targets), ['a1', 'a2']);
      expect(targets.first.ambiguous, isFalse);
    });

    test('"song … by …" is understood', () {
      final targets = plan(
        const VoiceRequest(query: 'the song angel by artist two'),
        index,
      );
      expect(songIds(targets).first, 'a2');
    });
  });

  group('song, album and playlist with the same name', () {
    final index = VoiceLibraryIndex(
      tracks: [song('s', 'Locket'), song('x', 'Other')],
      albums: [album('al', 'locket')],
      playlists: const [
        MediaBrowsePlaylist(id: 'pl', name: 'Locket', trackCount: 2),
      ],
    );

    VoiceTarget first(VoiceRequest request) => plan(request, index).first;

    test('unstructured: the song', () {
      expect(first(const VoiceRequest(query: 'locket')), isA<VoiceSongs>());
    });

    test('each focus picks its own kind', () {
      expect(
        first(const VoiceRequest(query: 'locket', focus: VoiceFocus.song)),
        isA<VoiceSongs>(),
      );
      expect(
        first(const VoiceRequest(query: 'locket', focus: VoiceFocus.album)),
        isA<VoiceAlbum>(),
      );
      expect(
        first(const VoiceRequest(query: 'locket', focus: VoiceFocus.playlist)),
        isA<VoicePlaylist>(),
      );
    });

    for (final phrase in [
      'the album locket',
      'album locket',
      'locket album',
      'the locket album',
    ]) {
      test('"$phrase" plays the album', () {
        final target = first(VoiceRequest(query: phrase));
        expect((target as VoiceAlbum).album.albumId, 'al');
        expect(
          (first(VoiceRequest(query: phrase, focus: VoiceFocus.album))
                  as VoiceAlbum)
              .album
              .albumId,
          'al',
        );
      });
    }

    for (final phrase in [
      'playlist locket',
      'the playlist locket',
      'my playlist locket',
      'locket playlist',
      'my locket playlist',
    ]) {
      test('"$phrase" plays the playlist', () {
        final target = first(VoiceRequest(query: phrase));
        expect((target as VoicePlaylist).playlist.id, 'pl');
        expect(
          (first(VoiceRequest(query: phrase, focus: VoiceFocus.playlist))
                  as VoicePlaylist)
              .playlist
              .id,
          'pl',
        );
      });
    }

    for (final phrase in ['song locket', 'the song locket', 'track locket']) {
      test('"$phrase" plays the song', () {
        expect(songIds(plan(VoiceRequest(query: phrase), index)).first, 's');
        expect(
          songIds(
            plan(VoiceRequest(query: phrase, focus: VoiceFocus.song), index),
          ).first,
          's',
        );
      });
    }

    test('a typed phrase is not read against a different focus', () {
      expect(
        plan(
          const VoiceRequest(query: 'album locket', focus: VoiceFocus.song),
          index,
        ).whereType<VoiceAlbum>(),
        isEmpty,
      );
    });

    test('a query that is itself an exact name is not read as typed', () {
      final names = VoiceLibraryIndex(
        tracks: [song('blur', 'Song 2'), song('two', '2')],
        albums: [album('w', 'White Album'), album('x', 'White')],
      );

      expect(songIds(plan(const VoiceRequest(query: 'song 2'), names)), [
        'blur',
      ]);
      expect(
        (plan(const VoiceRequest(query: 'white album'), names).first
                as VoiceAlbum)
            .album
            .albumId,
        'w',
      );
    });

    test('"album X" with no such album plays songs named X', () {
      final noAlbum = VoiceLibraryIndex(tracks: index.tracks);
      expect(
        songIds(plan(const VoiceRequest(query: 'album locket'), noAlbum)).first,
        's',
      );
    });

    test('"the album X by Y" picks that artist\'s album', () {
      final albums = VoiceLibraryIndex(
        albums: [
          album('a1', 'Greatest Hits', artist: 'One'),
          album('a2', 'Greatest Hits', artist: 'Two'),
        ],
      );

      final targets = plan(
        const VoiceRequest(query: 'the album greatest hits by two'),
        albums,
      );
      expect((targets.first as VoiceAlbum).album.albumId, 'a2');
    });

    test('typed phrases are read as documented', () {
      expect(VoiceRequestResolver.typedQuery('the album Locket'), (
        VoiceFocus.album,
        'locket',
      ));
      expect(VoiceRequestResolver.typedQuery('my Gym playlist'), (
        VoiceFocus.playlist,
        'my gym',
      ));
      expect(VoiceRequestResolver.typedQuery('track Angel'), (
        VoiceFocus.song,
        'angel',
      ));
      expect(
        VoiceRequestResolver.typedQuery('Love Song'),
        isNull,
        reason: 'a trailing "song" is part of many titles',
      );
      expect(VoiceRequestResolver.typedQuery('album'), isNull);
      expect(VoiceRequestResolver.typedQuery('locket'), isNull);
    });
  });
}
