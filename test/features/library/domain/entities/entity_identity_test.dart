import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';

void main() {
  group('Permanent entity identity', () {
    final now = DateTime.utc(2026, 9, 10);

    test('artist copy preserves permanent identity', () {
      final artist = EntityFactory.createArtist(
        name: 'Original Name',
        now: now,
      );

      final renamed = artist.copyWith(
        name: 'New Name',
        canonicalName: 'new name',
      );

      expect(renamed.id, artist.id);
      expect(renamed, artist);
      expect(renamed.name, 'New Name');
    });

    test('album copy preserves permanent identity', () {
      final album = EntityFactory.createAlbum(
        artistId: 'artist_test',
        title: 'Original Album',
        now: now,
      );

      final renamed = album.copyWith(
        title: 'Renamed Album',
        canonicalTitle: 'renamed album',
      );

      expect(renamed.id, album.id);
      expect(renamed, album);
    });

    test('song copy preserves permanent identity', () {
      final song = EntityFactory.createSong(
        artistId: 'artist_test',
        albumId: 'album_test',
        albumEditionId: 'edition_test',
        title: 'Original Song',
        trackNumber: 1,
        durationSeconds: 200,
        now: now,
      );

      final edited = song.copyWith(
        title: 'Edited Song',
        canonicalTitle: 'edited song',
      );

      expect(edited.id, song.id);
      expect(edited, song);
    });

    test('different permanent IDs are different identities', () {
      final first = EntityFactory.createArtist(name: 'Same Artist', now: now);

      final second = EntityFactory.createArtist(name: 'Same Artist', now: now);

      expect(first.id, isNot(second.id));
      expect(first, isNot(second));
    });

    test('album edition nullable metadata can be cleared', () {
      final edition = EntityFactory.createAlbumEdition(
        albumId: 'album_test',
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        releaseDate: DateTime.utc(2026, 1, 1),
        genre: 'Pop',
        now: now,
      );

      final cleared = edition.copyWith(releaseDate: null, genre: null);

      expect(cleared.id, edition.id);
      expect(cleared.releaseDate, isNull);
      expect(cleared.genre, isNull);
    });
  });
}
