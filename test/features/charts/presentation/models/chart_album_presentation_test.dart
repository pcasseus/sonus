import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_album_presentation.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

void main() {
  final album = LibraryAlbum(
    albumId: 'album',
    title: 'Life Support',
    artistId: 'artist',
    artistName: 'Madison Beer',
    trackCount: 12,
    dateAdded: DateTime.utc(2026, 1, 1),
    primaryEditionId: 'standard',
    primaryEditionTitle: 'Standard',
    artworkPath: 'C:/covers/standard.jpg',
  );

  LibraryAlbumEdition edition(
    String id, {
    AlbumEditionType type = AlbumEditionType.deluxe,
    String albumId = 'album',
    DateTime? releaseDate,
    ReleaseDatePrecision? precision,
    DateTime? added,
    String? artworkPath,
  }) => LibraryAlbumEdition(
    editionId: id,
    albumId: albumId,
    title: 'Life Support ($id)',
    type: type,
    isPrimary: false,
    releaseDate: releaseDate,
    releaseDatePrecision: precision,
    dateAdded: added ?? DateTime.utc(2026, 1, 1),
    artworkPath: artworkPath ?? 'C:/covers/$id.jpg',
  );

  test('without a Deluxe the primary edition is shown', () {
    final shown = ChartAlbumPresentation.resolve(album, [
      edition('expanded', type: AlbumEditionType.expanded),
      edition('other-album', albumId: 'elsewhere'),
    ]);

    expect(shown.title, 'Life Support');
    expect(shown.artworkPath, 'C:/covers/standard.jpg');
    expect(shown.editionId, 'standard');
  });

  test('a Deluxe replaces the title, cover and edition opened', () {
    final shown = ChartAlbumPresentation.resolve(album, [edition('deluxe')]);

    expect(shown.title, 'Life Support (deluxe)');
    expect(shown.artworkPath, 'C:/covers/deluxe.jpg');
    expect(shown.editionId, 'deluxe');
  });

  test('a Deluxe without a cover keeps the placeholder', () {
    final shown = ChartAlbumPresentation.resolve(album, [
      edition('deluxe', artworkPath: '  '),
    ]);

    expect(shown.title, 'Life Support (deluxe)');
    expect(shown.artworkPath, isNull);
  });

  test('of several Deluxes the most recently released wins', () {
    final shown = ChartAlbumPresentation.resolve(album, [
      edition(
        'older',
        releaseDate: DateTime.utc(2024, 3, 1),
        added: DateTime.utc(2026, 6, 1),
      ),
      edition('newer', releaseDate: DateTime.utc(2025, 3, 1)),
      edition('oldest', releaseDate: DateTime.utc(2023, 3, 1)),
    ]);

    expect(shown.editionId, 'newer');
  });

  test('a dateless Deluxe makes the most recently added win', () {
    final shown = ChartAlbumPresentation.resolve(album, [
      edition(
        'dated',
        releaseDate: DateTime.utc(2025, 3, 1),
        added: DateTime.utc(2026, 2, 1),
      ),
      edition('dateless', added: DateTime.utc(2026, 5, 1)),
      edition('early', added: DateTime.utc(2026, 1, 1)),
    ]);

    expect(shown.editionId, 'dateless');
  });

  test('dates that could be the same day fall back to most recently added', () {
    final shown = ChartAlbumPresentation.resolve(album, [
      edition(
        'day',
        releaseDate: DateTime.utc(2025, 5, 1),
        added: DateTime.utc(2026, 1, 1),
      ),
      edition(
        'year',
        releaseDate: DateTime.utc(2025),
        precision: ReleaseDatePrecision.year,
        added: DateTime.utc(2026, 3, 1),
      ),
      edition('earlier', releaseDate: DateTime.utc(2024, 1, 1)),
    ]);

    expect(shown.editionId, 'year');
  });

  test('identical dates and additions break the tie by edition id', () {
    final date = DateTime.utc(2025, 5, 1);
    final first = ChartAlbumPresentation.resolve(album, [
      edition('a', releaseDate: date),
      edition('b', releaseDate: date),
    ]);
    final second = ChartAlbumPresentation.resolve(album, [
      edition('b', releaseDate: date),
      edition('a', releaseDate: date),
    ]);

    expect(first.editionId, 'b');
    expect(second.editionId, 'b');
  });
}
