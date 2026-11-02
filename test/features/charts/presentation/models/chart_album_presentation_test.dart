import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_album_presentation.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_release_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';

void main() {
  final album = LibraryAlbum(
    albumId: 'album',
    title: 'Locket',
    artistId: 'artist',
    artistName: 'Madison Beer',
    trackCount: 12,
    dateAdded: DateTime.utc(2026, 1, 1),
    primaryEditionId: 'standard',
    primaryEditionTitle: 'Standard',
    artworkPath: 'C:/covers/standard.jpg',
  );

  LibraryReleaseEdition edition(
    String id, {
    required int tracks,
    AlbumEditionType type = AlbumEditionType.deluxe,
    String albumId = 'album',
    String? title,
    DateTime? releaseDate,
    ReleaseDatePrecision? precision,
    DateTime? added,
    String? artworkPath,
  }) => LibraryReleaseEdition(
    edition: LibraryAlbumEdition(
      editionId: id,
      albumId: albumId,
      title: title ?? 'Locket ($id)',
      type: type,
      isPrimary: id == 'standard',
      releaseDate: releaseDate,
      releaseDatePrecision: precision,
      dateAdded: added ?? DateTime.utc(2026, 1, 1),
      artworkPath: artworkPath ?? 'C:/covers/$id.jpg',
    ),
    trackCount: tracks,
  );

  LibraryReleaseEdition standard(int tracks) => edition(
    'standard',
    tracks: tracks,
    type: AlbumEditionType.standard,
    title: 'Locket',
    // The primary edition is shown exactly as the album is.
    artworkPath: 'C:/covers/standard-edition-row.jpg',
  );

  group('the edition with the most songs represents the release', () {
    test('a longer Deluxe shows its title, cover and edition together', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('deluxe', tracks: 16, title: 'Locket (Deluxe)'),
      ]);

      expect(shown.title, 'Locket (Deluxe)');
      expect(shown.artworkPath, 'C:/covers/deluxe.jpg');
      expect(shown.editionId, 'deluxe');
    });

    test('a longer standard edition wins over a shorter Deluxe', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(14),
        edition('deluxe', tracks: 4),
      ]);

      expect(shown.title, 'Locket');
      expect(shown.artworkPath, 'C:/covers/standard.jpg');
      expect(shown.editionId, 'standard');
    });

    test('any edition type can win, not only a Deluxe', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('deluxe', tracks: 15),
        edition('expanded', tracks: 20, type: AlbumEditionType.expanded),
      ]);

      expect(shown.title, 'Locket (expanded)');
      expect(shown.artworkPath, 'C:/covers/expanded.jpg');
      expect(shown.editionId, 'expanded');
    });

    test('other releases\' editions are ignored', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('elsewhere', tracks: 40, albumId: 'other-album'),
      ]);

      expect(shown.editionId, 'standard');
    });
  });

  group('ties', () {
    test('a Deluxe as long as the standard edition is shown', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('deluxe', tracks: 12),
      ]);

      expect(shown.editionId, 'deluxe');
    });

    test('without a tied Deluxe the primary edition is shown', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('expanded', tracks: 12, type: AlbumEditionType.expanded),
      ]);

      expect(shown.title, 'Locket');
      expect(shown.editionId, 'standard');
    });

    test('of tied Deluxes the most recently released wins', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(10),
        edition(
          'older',
          tracks: 16,
          releaseDate: DateTime.utc(2024, 3, 1),
          added: DateTime.utc(2026, 6, 1),
        ),
        edition('newer', tracks: 16, releaseDate: DateTime.utc(2025, 3, 1)),
        // Longest wins before any recency.
        edition('short', tracks: 11, releaseDate: DateTime.utc(2026, 3, 1)),
      ]);

      expect(shown.editionId, 'newer');
    });

    test('a dateless tied Deluxe makes the most recently added win', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        edition(
          'dated',
          tracks: 16,
          releaseDate: DateTime.utc(2025, 3, 1),
          added: DateTime.utc(2026, 2, 1),
        ),
        edition('dateless', tracks: 16, added: DateTime.utc(2026, 5, 1)),
      ]);

      expect(shown.editionId, 'dateless');
    });

    test(
      'dates that could be the same day fall back to most recently added',
      () {
        final shown = ChartAlbumPresentation.resolve(album, [
          edition(
            'day',
            tracks: 16,
            releaseDate: DateTime.utc(2025, 5, 1),
            added: DateTime.utc(2026, 1, 1),
          ),
          edition(
            'year',
            tracks: 16,
            releaseDate: DateTime.utc(2025),
            precision: ReleaseDatePrecision.year,
            added: DateTime.utc(2026, 3, 1),
          ),
        ]);

        expect(shown.editionId, 'year');
      },
    );

    test('tied non-primary editions are ordered the same way', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(8),
        edition(
          'remaster',
          tracks: 18,
          type: AlbumEditionType.remaster,
          releaseDate: DateTime.utc(2025, 1, 1),
        ),
        edition(
          'anniversary',
          tracks: 18,
          type: AlbumEditionType.anniversary,
          releaseDate: DateTime.utc(2026, 1, 1),
        ),
      ]);

      expect(shown.editionId, 'anniversary');
    });

    test('the result does not depend on the order editions arrive in', () {
      final date = DateTime.utc(2025, 5, 1);
      final first = ChartAlbumPresentation.resolve(album, [
        edition('a', tracks: 16, releaseDate: date),
        edition('b', tracks: 16, releaseDate: date),
      ]);
      final second = ChartAlbumPresentation.resolve(album, [
        edition('b', tracks: 16, releaseDate: date),
        edition('a', tracks: 16, releaseDate: date),
      ]);

      expect(first.editionId, 'b');
      expect(second.editionId, 'b');
    });
  });

  group('artwork', () {
    test('a winning edition without a cover keeps the placeholder', () {
      final shown = ChartAlbumPresentation.resolve(album, [
        standard(12),
        edition('deluxe', tracks: 16, artworkPath: '  '),
      ]);

      expect(shown.title, 'Locket (deluxe)');
      // Never another edition's cover (A-Q28).
      expect(shown.artworkPath, isNull);
    });

    test('a primary winner without a cover keeps the placeholder', () {
      final coverless = LibraryAlbum(
        albumId: 'album',
        title: 'Locket',
        artistId: 'artist',
        artistName: 'Madison Beer',
        trackCount: 12,
        dateAdded: DateTime.utc(2026, 1, 1),
        primaryEditionId: 'standard',
      );

      final shown = ChartAlbumPresentation.resolve(coverless, [
        standard(12),
        edition('deluxe', tracks: 3),
      ]);

      expect(shown.editionId, 'standard');
      expect(shown.artworkPath, isNull);
    });
  });

  group('without song counts the primary edition is shown', () {
    test('when no editions were read', () {
      final shown = ChartAlbumPresentation.resolve(album, const []);

      expect(shown.title, 'Locket');
      expect(shown.artworkPath, 'C:/covers/standard.jpg');
      expect(shown.editionId, 'standard');
    });
  });
}
