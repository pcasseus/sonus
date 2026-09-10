import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/identity/library_identity_resolver.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/album_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';

class FakeArtistRepository implements ArtistRepository {
  FakeArtistRepository(this.items);

  final List<Artist> items;

  @override
  Future<void> create(Artist artist) async {}

  @override
  Future<List<Artist>> getAll() async => items;

  @override
  Future<Artist?> getById(String id) async {
    return items.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<void> save(Artist artist) async {}
}

class FakeAlbumRepository implements AlbumRepository {
  FakeAlbumRepository(this.items);

  final List<Album> items;

  @override
  Future<void> create(Album album) async {}

  @override
  Future<List<Album>> getByArtistId(String artistId) async {
    return items.where((item) => item.artistId == artistId).toList();
  }

  @override
  Future<Album?> getById(String id) async {
    return items.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<void> save(Album album) async {}
}

class FakeAlbumEditionRepository implements AlbumEditionRepository {
  FakeAlbumEditionRepository(this.items);

  final List<AlbumEdition> items;

  @override
  Future<void> create(AlbumEdition edition) async {}

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async {
    return items.where((item) => item.albumId == albumId).toList();
  }

  @override
  Future<AlbumEdition?> getById(String id) async {
    return items.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<void> save(AlbumEdition edition) async {}
}

class FakeSongRepository implements SongRepository {
  FakeSongRepository(this.items);

  final List<Song> items;

  @override
  Future<void> create(Song song) async {}

  @override
  Future<List<Song>> getByAlbumId(String albumId) async {
    return items.where((item) => item.albumId == albumId).toList();
  }

  @override
  Future<List<Song>> getByArtistId(String artistId) async {
    return items.where((item) => item.artistId == artistId).toList();
  }

  @override
  Future<List<Song>> getByEditionId(String editionId) async {
    return items.where((item) => item.albumEditionId == editionId).toList();
  }

  @override
  Future<Song?> getById(String id) async {
    return items.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<void> save(Song song) async {}
}

void main() {
  final now = DateTime.utc(2026, 9, 10);

  final artist = Artist(
    id: 'artist_existing',
    name: 'Artist Name',
    canonicalName: 'artist name',
    createdAt: now,
    updatedAt: now,
  );

  final album = Album(
    id: 'album_existing',
    artistId: artist.id,
    title: 'Album Name',
    canonicalTitle: 'album name',
    createdAt: now,
    updatedAt: now,
  );

  final edition = AlbumEdition(
    id: 'edition_existing',
    albumId: album.id,
    title: 'Album Name',
    type: AlbumEditionType.standard,
    isPrimary: true,
    createdAt: now,
    updatedAt: now,
  );

  final song = Song(
    id: 'song_existing',
    artistId: artist.id,
    albumId: album.id,
    albumEditionId: edition.id,
    title: 'Song Name',
    canonicalTitle: 'song name',
    trackNumber: 1,
    durationSeconds: 200,
    isSingle: false,
    featuredArtists: const [],
    createdAt: now,
    updatedAt: now,
  );

  AudioMetadata metadata({
    String artistName = 'Artist Name',
    String albumTitle = 'Album Name',
    String title = 'Song Name',
  }) {
    return AudioMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      durationSeconds: 200,
      trackNumber: 1,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  LibraryIdentityResolver resolver({
    List<Artist>? artists,
    List<Album>? albums,
    List<AlbumEdition>? editions,
    List<Song>? songs,
  }) {
    return LibraryIdentityResolver(
      artistRepository: FakeArtistRepository(artists ?? [artist]),
      albumRepository: FakeAlbumRepository(albums ?? [album]),
      albumEditionRepository: FakeAlbumEditionRepository(editions ?? [edition]),
      songRepository: FakeSongRepository(songs ?? [song]),
    );
  }

  test('resolves existing graph without changing permanent IDs', () async {
    final result = await resolver().resolve(metadata());

    expect(result.artist?.id, 'artist_existing');
    expect(result.album?.id, 'album_existing');
    expect(result.edition?.id, 'edition_existing');
    expect(result.song?.id, 'song_existing');
    expect(result.hasAmbiguity, isFalse);
  });

  test('returns no artist when canonical artist does not exist', () async {
    final result = await resolver(artists: []).resolve(metadata());

    expect(result.artist, isNull);
    expect(result.artistAmbiguous, isFalse);
  });

  test('flags artist ambiguity instead of guessing', () async {
    final secondArtist = Artist(
      id: 'artist_second',
      name: 'Artist Name',
      canonicalName: 'artist name',
      createdAt: now,
      updatedAt: now,
    );

    final result = await resolver(
      artists: [artist, secondArtist],
    ).resolve(metadata());

    expect(result.artist, isNull);
    expect(result.artistAmbiguous, isTrue);
    expect(result.hasAmbiguity, isTrue);
  });

  test('flags duplicate album matches instead of guessing', () async {
    final secondAlbum = Album(
      id: 'album_second',
      artistId: artist.id,
      title: 'Album Name',
      canonicalTitle: 'album name',
      createdAt: now,
      updatedAt: now,
    );

    final result = await resolver(
      albums: [album, secondAlbum],
    ).resolve(metadata());

    expect(result.artist?.id, artist.id);
    expect(result.album, isNull);
    expect(result.albumAmbiguous, isTrue);
  });

  test('flags duplicate song titles within an edition', () async {
    final secondSong = Song(
      id: 'song_second',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Song Name',
      canonicalTitle: 'song name',
      trackNumber: 2,
      durationSeconds: 201,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

    final result = await resolver(
      songs: [song, secondSong],
    ).resolve(metadata());

    expect(result.song, isNull);
    expect(result.songAmbiguous, isTrue);
  });

  test('multiple unresolved album editions are treated as ambiguous', () async {
    final now = DateTime.utc(2026, 9, 10, 12);

    final artist = Artist(
      id: 'artist_existing',
      name: 'Artist Name',
      canonicalName: 'artist name',
      createdAt: now,
      updatedAt: now,
    );

    final album = Album(
      id: 'album_existing',
      artistId: artist.id,
      title: 'Album Name',
      canonicalTitle: 'album name',
      createdAt: now,
      updatedAt: now,
    );

    final editionOne = AlbumEdition(
      id: 'edition_one',
      albumId: album.id,
      title: 'Edition One',
      type: AlbumEditionType.other,
      isPrimary: false,
      createdAt: now,
      updatedAt: now,
    );

    final editionTwo = AlbumEdition(
      id: 'edition_two',
      albumId: album.id,
      title: 'Edition Two',
      type: AlbumEditionType.other,
      isPrimary: false,
      createdAt: now,
      updatedAt: now,
    );

    final resolver = LibraryIdentityResolver(
      artistRepository: FakeArtistRepository([artist]),
      albumRepository: FakeAlbumRepository([album]),
      albumEditionRepository: FakeAlbumEditionRepository([
        editionOne,
        editionTwo,
      ]),
      songRepository: FakeSongRepository(const []),
    );

    final result = await resolver.resolve(
      const AudioMetadata(
        title: 'Song Name',
        artistName: 'Artist Name',
        albumTitle: 'Album Name',
        durationSeconds: 200,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: [],
      ),
    );

    expect(result.artist, artist);
    expect(result.album, album);
    expect(result.edition, isNull);
    expect(result.editionAmbiguous, isTrue);
    expect(result.hasAmbiguity, isTrue);
  });
}
