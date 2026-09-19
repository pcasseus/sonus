import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';

import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/import/presentation/pages/import_review_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/repositories/album_edition_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 17, 12);

  LibraryTrack track(String id, String title) {
    return LibraryTrack(
      songId: id,
      title: title,
      artistId: 'artist-$id',
      artistName: 'Unknown Artist',
      albumId: 'album-$id',
      albumTitle: 'Unknown Album',
      albumEditionId: 'edition-$id',
      albumEditionTitle: 'Unknown Album',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 0,
      durationSeconds: 0,
      isSingle: false,
      featuredArtists: const ['Guest'],
      dateAdded: createdAt,
      filePath: 'C:/Music/$id.mp3',
      isAvailable: true,
    );
  }

  LibraryAlbum albumForSong(String songId) {
    return LibraryAlbum(
      albumId: 'album-$songId',
      title: 'Unknown Album',
      artistId: 'artist-$songId',
      artistName: 'Unknown Artist',
      primaryEditionId: 'edition-$songId',
      primaryEditionTitle: 'Standard',
      primaryEditionType: AlbumEditionType.standard,
      releaseDate: DateTime.utc(2024, 5, 17),
      genre: 'Pop',
      trackCount: 1,
      dateAdded: createdAt,
    );
  }

  SongImportReview review(String id) {
    return SongImportReview(
      songId: id,
      metadataSource: MetadataSource.fallback,
      reasons: const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.unknownArtist,
      ],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  Future<_Harness> pumpReviewPage(
    WidgetTester tester, {
    required List<SongImportReview> reviews,
    required Map<String, LibraryTrack> tracks,
    Object? editError,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    List<LibraryAlbum> albums = const [],
    List<LibraryArtist> artists = const [],
    AlbumProfileEditingService? albumProfileEditingService,
  }) async {
    final reviewRepository = _FakeReviewRepository(reviews);
    final editingService = _FakeEditingService(error: editError);
    final libraryRepository = _FakeLibraryRepository(
      tracks,
      albums: albums,
      artists: artists,
    );
    final artistCreationService = _FakeArtistCreationService(
      libraryRepository: libraryRepository,
    );

    final service = ImportReviewService(
      reviewRepository: reviewRepository,
      libraryQueryRepository: libraryRepository,
      trackProfileEditingService: editingService,
      artistCreationService: artistCreationService,
      now: () => DateTime.utc(2026, 9, 17, 13),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImportReviewPage(
          service: service,
          userId: 'user-1',
          artworkAssignmentService: artworkAssignmentService,
          artworkFilePicker: artworkFilePicker,
          albumProfileEditingService: albumProfileEditingService,
        ),
      ),
    );

    await tester.pumpAndSettle();

    return _Harness(
      reviewRepository: reviewRepository,
      editingService: editingService,
      artistCreationService: artistCreationService,
    );
  }

  testWidgets('shows current review and reason labels', (tester) async {
    await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Imported Song')},
    );

    expect(
      find.byKey(const ValueKey<String>('import-review-page')),
      findsOneWidget,
    );
    expect(find.text('Imported Song'), findsOneWidget);
    expect(find.text('Unknown Artist'), findsOneWidget);
    expect(find.text('Unknown Album'), findsOneWidget);
    expect(find.text('Metadata guessed from file or folder'), findsOneWidget);
    expect(find.text('Unknown artist'), findsOneWidget);
  });

  testWidgets('shows loose folder review reason label', (tester) async {
    await pumpReviewPage(
      tester,
      reviews: [
        SongImportReview(
          songId: 'song-1',
          metadataSource: MetadataSource.embedded,
          reasons: const [ImportReviewReason.looseFolder],
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      tracks: {'song-1': track('song-1', 'Loose Album Song')},
    );

    expect(find.text('Loose folder structure'), findsOneWidget);
  });
  testWidgets('Previous and Next browse reviews without resolving them', (
    tester,
  ) async {
    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1'), review('song-2'), review('song-3')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
        'song-3': track('song-3', 'Third Song'),
      },
    );

    final previousButton = find.byKey(
      const ValueKey<String>('import-review-previous-button'),
    );
    final nextButton = find.byKey(
      const ValueKey<String>('import-review-next-button'),
    );

    expect(find.text('3 songs need review'), findsOneWidget);
    expect(find.text('Song 1 of 3'), findsOneWidget);
    expect(find.text('First Song'), findsOneWidget);

    expect(tester.widget<OutlinedButton>(previousButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(nextButton).onPressed, isNotNull);

    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(find.text('Song 2 of 3'), findsOneWidget);
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('First Song'), findsNothing);
    expect(find.text('3 songs need review'), findsOneWidget);

    final firstReview = await harness.reviewRepository.getBySongId('song-1');
    final secondReview = await harness.reviewRepository.getBySongId('song-2');

    expect(firstReview, isNotNull);
    expect(firstReview!.needsReview, isTrue);
    expect(firstReview.resolvedAt, isNull);

    expect(secondReview, isNotNull);
    expect(secondReview!.needsReview, isTrue);
    expect(secondReview.resolvedAt, isNull);

    await tester.tap(previousButton);
    await tester.pumpAndSettle();

    expect(find.text('Song 1 of 3'), findsOneWidget);
    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('3 songs need review'), findsOneWidget);
  });

  testWidgets('review navigation disables buttons at queue boundaries', (
    tester,
  ) async {
    await pumpReviewPage(
      tester,
      reviews: [review('song-1'), review('song-2')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      },
    );

    final previousButton = find.byKey(
      const ValueKey<String>('import-review-previous-button'),
    );
    final nextButton = find.byKey(
      const ValueKey<String>('import-review-next-button'),
    );

    expect(find.text('Song 1 of 2'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(previousButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(nextButton).onPressed, isNotNull);

    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(find.text('Song 2 of 2'), findsOneWidget);
    expect(find.text('Second Song'), findsOneWidget);

    expect(tester.widget<OutlinedButton>(previousButton).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(nextButton).onPressed, isNull);
  });
  testWidgets('edit dialog is prefilled and cancel does not resolve review', (
    tester,
  ) async {
    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Imported Song')},
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('import-review-edit-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit song details'), findsOneWidget);

    final titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-title-field')),
    );
    final numberField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-number-field')),
    );
    final featuredField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
    );

    expect(titleField.controller!.text, 'Imported Song');
    expect(numberField.controller!.text, '0');
    expect(featuredField.controller!.text, 'Guest');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Edit song details'), findsNothing);
    expect(find.text('Imported Song'), findsOneWidget);
    expect(harness.editingService.updateCallCount, 0);

    final stored = await harness.reviewRepository.getBySongId('song-1');

    expect(stored, isNotNull);
    expect(stored!.needsReview, isTrue);
    expect(stored.resolvedAt, isNull);
  });

  testWidgets('saving first review advances to next song', (tester) async {
    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1'), review('song-2')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      },
    );

    expect(find.text('2 songs need review'), findsOneWidget);
    expect(find.text('First Song'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('import-review-edit-button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-title-field')),
      'Corrected First Song',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-number-field')),
      '1',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
    await tester.pumpAndSettle();

    expect(harness.editingService.updateCallCount, 1);
    expect(harness.editingService.lastSongId, 'song-1');
    expect(harness.editingService.lastTitle, 'Corrected First Song');

    expect(find.text('1 song need review'), findsOneWidget);
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('First Song'), findsNothing);

    final firstReview = await harness.reviewRepository.getBySongId('song-1');

    expect(firstReview, isNotNull);
    expect(firstReview!.isResolved, isTrue);
  });

  testWidgets('saving final review shows all caught up state', (tester) async {
    await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Only Song')},
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('import-review-edit-button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-number-field')),
      '1',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('import-review-complete')),
      findsOneWidget,
    );
    expect(find.text('All caught up'), findsOneWidget);
    expect(
      find.text('There are no imported songs waiting for metadata review.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'artwork buttons appear and change artwork without resolving review',
    (tester) async {
      final songRepository = _FakeSongRepository([
        _songForArtwork('song-1', artworkId: 'artwork-old'),
      ]);

      final artworkRepository = _FakeArtworkAssetRepository();

      final harness = await pumpReviewPage(
        tester,
        reviews: [review('song-1')],
        tracks: {'song-1': track('song-1', 'Needs Review')},
        artworkAssignmentService: _artworkService(
          artworkRepository: artworkRepository,
          songRepository: songRepository,
        ),
        artworkFilePicker: const _FakeArtworkFilePicker(
          filePath: r'C:\Artwork\Replacement.jpg',
        ),
      );

      expect(
        find.byKey(
          const ValueKey<String>('import-review-change-artwork-button'),
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(
          const ValueKey<String>('import-review-clear-artwork-button'),
        ),
        findsOneWidget,
      );

      final changeArtworkButton = find.byKey(
        const ValueKey<String>('import-review-change-artwork-button'),
      );

      await tester.ensureVisible(changeArtworkButton);
      await tester.pumpAndSettle();

      await tester.tap(changeArtworkButton);

      await tester.pumpAndSettle();

      expect(find.text('Song artwork updated.'), findsOneWidget);
      expect(find.text('Needs Review'), findsOneWidget);

      final storedReview = await harness.reviewRepository.getBySongId('song-1');

      expect(storedReview, isNotNull);
      expect(storedReview!.needsReview, isTrue);
      expect(storedReview.resolvedAt, isNull);

      final savedSong = await songRepository.getById('song-1');

      expect(savedSong, isNotNull);
      expect(savedSong!.artworkId, isNot('artwork-old'));
    },
  );

  testWidgets('clear artwork keeps current review unresolved', (tester) async {
    final songRepository = _FakeSongRepository([
      _songForArtwork('song-1', artworkId: 'artwork-existing'),
    ]);

    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      artworkAssignmentService: _artworkService(songRepository: songRepository),
      artworkFilePicker: const _FakeArtworkFilePicker(
        filePath: r'C:\Artwork\Unused.jpg',
      ),
    );

    final clearArtworkButton = find.byKey(
      const ValueKey<String>('import-review-clear-artwork-button'),
    );

    await tester.ensureVisible(clearArtworkButton);
    await tester.pumpAndSettle();

    await tester.tap(clearArtworkButton);
    await tester.pumpAndSettle();

    expect(find.text('Song artwork cleared.'), findsOneWidget);
    expect(find.text('Needs Review'), findsOneWidget);

    final storedReview = await harness.reviewRepository.getBySongId('song-1');

    expect(storedReview, isNotNull);
    expect(storedReview!.needsReview, isTrue);
    expect(storedReview.resolvedAt, isNull);

    final savedSong = await songRepository.getById('song-1');

    expect(savedSong, isNotNull);
    expect(savedSong!.artworkId, isNull);
  });
  testWidgets('change album artwork keeps current review unresolved', (
    tester,
  ) async {
    final songRepository = _FakeSongRepository([_songForArtwork('song-1')]);
    final albumEditionRepository = _FakeAlbumEditionRepository([
      _albumEditionForArtwork('song-1', artworkId: 'album-artwork-existing'),
    ]);
    final artworkRepository = _FakeArtworkAssetRepository();

    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      albums: [albumForSong('song-1')],
      artworkAssignmentService: _artworkService(
        artworkRepository: artworkRepository,
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
      ),
      artworkFilePicker: const _FakeArtworkFilePicker(
        filePath: r'C:\Artwork\AlbumReplacement.jpg',
      ),
    );

    final changeButton = find.byKey(
      const ValueKey<String>('import-review-change-album-artwork-button'),
    );

    expect(changeButton, findsOneWidget);

    await tester.ensureVisible(changeButton);
    await tester.pumpAndSettle();

    await tester.tap(changeButton);
    await tester.pumpAndSettle();

    expect(find.text('Album artwork updated.'), findsOneWidget);
    expect(find.text('Needs Review'), findsOneWidget);

    final storedReview = await harness.reviewRepository.getBySongId('song-1');

    expect(storedReview, isNotNull);
    expect(storedReview!.needsReview, isTrue);
    expect(storedReview.resolvedAt, isNull);

    final savedEdition = await albumEditionRepository.getById('edition-song-1');

    expect(savedEdition, isNotNull);
    expect(savedEdition!.artworkId, isNot('album-artwork-existing'));
  });

  testWidgets('clear album artwork keeps current review unresolved', (
    tester,
  ) async {
    final songRepository = _FakeSongRepository([_songForArtwork('song-1')]);
    final albumEditionRepository = _FakeAlbumEditionRepository([
      _albumEditionForArtwork('song-1', artworkId: 'album-artwork-existing'),
    ]);

    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      albums: [albumForSong('song-1')],
      artworkAssignmentService: _artworkService(
        albumEditionRepository: albumEditionRepository,
        songRepository: songRepository,
      ),
      artworkFilePicker: const _FakeArtworkFilePicker(
        filePath: r'C:\Artwork\Unused.jpg',
      ),
    );

    final clearButton = find.byKey(
      const ValueKey<String>('import-review-clear-album-artwork-button'),
    );

    expect(clearButton, findsOneWidget);

    await tester.ensureVisible(clearButton);
    await tester.pumpAndSettle();

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('Album artwork cleared.'), findsOneWidget);
    expect(find.text('Needs Review'), findsOneWidget);

    final storedReview = await harness.reviewRepository.getBySongId('song-1');

    expect(storedReview, isNotNull);
    expect(storedReview!.needsReview, isTrue);
    expect(storedReview.resolvedAt, isNull);

    final savedEdition = await albumEditionRepository.getById('edition-song-1');

    expect(savedEdition, isNotNull);
    expect(savedEdition!.artworkId, isNull);
  });
  testWidgets('album editor saves without resolving current review', (
    tester,
  ) async {
    final albumEditingService = _FakeAlbumProfileEditingService();

    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      albums: [albumForSong('song-1')],
      albumProfileEditingService: albumEditingService,
    );

    final albumButton = find.byKey(
      const ValueKey<String>('import-review-edit-album-button'),
    );

    expect(albumButton, findsOneWidget);

    await tester.ensureVisible(albumButton);
    await tester.pumpAndSettle();

    await tester.tap(albumButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit album details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('album-title-field')),
      findsOneWidget,
    );

    final titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('album-title-field')),
    );

    expect(titleField.controller!.text, 'Unknown Album');

    await tester.enterText(
      find.byKey(const ValueKey<String>('album-title-field')),
      'Corrected Album',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('album-edit-save-button')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('import-review-position')),
    );
    await tester.pumpAndSettle();

    expect(albumEditingService.updateCallCount, 1);
    expect(albumEditingService.lastAlbumId, 'album-song-1');
    expect(albumEditingService.lastPrimaryEditionId, 'edition-song-1');
    expect(albumEditingService.lastTitle, 'Corrected Album');

    expect(find.text('Needs Review'), findsOneWidget);
    expect(
      find.text('Album details updated. This song still needs review.'),
      findsOneWidget,
    );

    final storedReview = await harness.reviewRepository.getBySongId('song-1');

    expect(storedReview, isNotNull);
    expect(storedReview!.needsReview, isTrue);
    expect(storedReview.resolvedAt, isNull);
  });
  testWidgets('failed save keeps same review visible and unresolved', (
    tester,
  ) async {
    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      editError: StateError('edit failed'),
    );

    final editButton = find.byKey(
      const ValueKey<String>('import-review-edit-button'),
    );

    await tester.ensureVisible(editButton);
    await tester.pumpAndSettle();

    await tester.tap(editButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-number-field')),
      '1',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('track-edit-save-button')),
    );
    await tester.pumpAndSettle();

    final errorBanner = find.byKey(
      const ValueKey<String>('import-review-error'),
    );

    await tester.ensureVisible(errorBanner);
    await tester.pumpAndSettle();

    expect(harness.editingService.updateCallCount, 1);

    expect(
      find.byKey(const ValueKey<String>('import-review-error')),
      findsOneWidget,
    );
    expect(find.text('Needs Review'), findsOneWidget);

    final stored = await harness.reviewRepository.getBySongId('song-1');

    expect(stored, isNotNull);
    expect(stored!.needsReview, isTrue);
    expect(stored.resolvedAt, isNull);
  });

  testWidgets('Needs Review can create a primary artist and save its id', (
    tester,
  ) async {
    final harness = await pumpReviewPage(
      tester,
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Faster than Boyz')},
    );

    final editButton = find.byKey(
      const ValueKey<String>('import-review-edit-button'),
    );
    await tester.ensureVisible(editButton);
    await tester.pumpAndSettle();
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    final titleField = find.byKey(const ValueKey<String>('track-title-field'));
    await tester.enterText(titleField, 'Faster than Boyz');

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-number-field')),
      '5',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-disc-number-field')),
      '3',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('track-featured-artists-field')),
      'Ariana Grande',
    );

    final addArtistButton = find.byKey(
      const ValueKey<String>('track-add-primary-artist-button'),
    );
    await tester.ensureVisible(addArtistButton);
    await tester.pumpAndSettle();
    await tester.tap(addArtistButton);
    await tester.pumpAndSettle();

    expect(find.text('Add new artist'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('track-new-artist-name-field')),
      '  Victoria Justice  ',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('track-new-artist-save-button')),
    );
    await tester.pumpAndSettle();

    expect(harness.artistCreationService.lastRequestedUserId, 'user-1');
    expect(harness.artistCreationService.lastRequestedName, 'Victoria Justice');

    expect(find.text('Edit song details'), findsOneWidget);
    expect(find.text('Victoria Justice'), findsOneWidget);

    final saveButton = find.byKey(
      const ValueKey<String>('track-edit-save-button'),
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(harness.editingService.updateCallCount, 1);
    expect(harness.editingService.lastSongId, 'song-1');
    expect(harness.editingService.lastArtistId, 'artist-created');
    expect(harness.editingService.lastTitle, 'Faster than Boyz');

    expect(
      find.byKey(const ValueKey<String>('import-review-complete')),
      findsOneWidget,
    );

    final storedReview = await harness.reviewRepository.getBySongId('song-1');

    expect(storedReview, isNotNull);
    expect(storedReview!.isResolved, isTrue);
  });
}

class _Harness {
  const _Harness({
    required this.reviewRepository,
    required this.editingService,
    required this.artistCreationService,
  });

  final _FakeReviewRepository reviewRepository;
  final _FakeEditingService editingService;
  final _FakeArtistCreationService artistCreationService;
}

class _FakeReviewRepository implements SongImportReviewRepository {
  _FakeReviewRepository(List<SongImportReview> reviews)
    : _reviews = {for (final review in reviews) review.songId: review};

  final Map<String, SongImportReview> _reviews;

  @override
  Future<void> create(SongImportReview review) async {
    _reviews[review.songId] = review;
  }

  @override
  Future<void> save(SongImportReview review) async {
    _reviews[review.songId] = review;
  }

  @override
  Future<SongImportReview?> getBySongId(String songId) async {
    return _reviews[songId];
  }

  @override
  Future<List<SongImportReview>> getUnresolved() async {
    return _reviews.values
        .where((review) => review.needsReview)
        .toList(growable: false);
  }

  @override
  Future<int> countUnresolved() async {
    return _reviews.values.where((review) => review.needsReview).length;
  }
}

class _FakeLibraryRepository implements LibraryQueryRepository {
  _FakeLibraryRepository(
    this.tracks, {
    this.albums = const [],
    List<LibraryArtist> artists = const [],
  }) : artists = List<LibraryArtist>.from(artists);

  final Map<String, LibraryTrack> tracks;
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => tracks[songId];

  @override
  Future<List<LibraryArtist>> getArtists() async =>
      List<LibraryArtist>.unmodifiable(artists);

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => tracks.values.toList(growable: false);

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    for (final artist in artists) {
      if (artist.artistId == artistId) {
        return artist;
      }
    }

    return null;
  }
}

class _FakeEditingService extends TrackProfileEditingService {
  _FakeEditingService({this.error})
    : super(mutationRunner: _UnusedMutationRunner());

  final Object? error;

  int updateCallCount = 0;
  String? lastSongId;
  String? lastTitle;
  String? lastArtistId;

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String userId,
    required String songId,
    required String title,
    required int trackNumber,
    int discNumber = 1,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) async {
    updateCallCount++;
    lastSongId = songId;
    lastTitle = title;
    lastArtistId = artistId;

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    final timestamp = now ?? DateTime.utc(2026, 9, 17, 13);

    return TrackProfileEditResult(
      song: Song(
        id: songId,
        artistId: artistId ?? 'artist-$songId',
        albumId: albumId ?? 'album-$songId',
        albumEditionId: albumEditionId ?? 'edition-$songId',
        title: title,
        canonicalTitle: title.trim().toLowerCase(),
        trackNumber: trackNumber,
        discNumber: discNumber,
        durationSeconds: 180,
        isSingle: isSingle,
        featuredArtists: List<String>.from(featuredArtists),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      changed: true,
    );
  }
}

ArtworkAssignmentService _artworkService({
  _FakeArtworkAssetRepository? artworkRepository,
  _FakeAlbumEditionRepository? albumEditionRepository,
  required _FakeSongRepository songRepository,
}) {
  return ArtworkAssignmentService(
    artworkAssetRepository: artworkRepository ?? _FakeArtworkAssetRepository(),
    artistRepository: _FakeArtistRepository(),
    albumEditionRepository:
        albumEditionRepository ?? _FakeAlbumEditionRepository(),
    songRepository: songRepository,
  );
}

AlbumEdition _albumEditionForArtwork(String songId, {String? artworkId}) {
  return AlbumEdition(
    id: 'edition-$songId',
    albumId: 'album-$songId',
    title: 'Standard',
    type: AlbumEditionType.standard,
    isPrimary: true,
    artworkId: artworkId,
    createdAt: DateTime.utc(2026, 9, 17, 12),
    updatedAt: DateTime.utc(2026, 9, 17, 12),
  );
}

Song _songForArtwork(String id, {String? artworkId}) {
  return Song(
    id: id,
    artistId: 'artist-$id',
    albumId: 'album-$id',
    albumEditionId: 'edition-$id',
    title: 'Needs Review',
    canonicalTitle: 'needs review',
    trackNumber: 0,
    durationSeconds: 0,
    isSingle: false,
    featuredArtists: const [],
    artworkId: artworkId,
    createdAt: DateTime.utc(2026, 9, 17, 12),
    updatedAt: DateTime.utc(2026, 9, 17, 12),
  );
}

class _FakeArtworkFilePicker implements ArtworkFilePicker {
  const _FakeArtworkFilePicker({this.filePath});

  final String? filePath;

  @override
  Future<String?> pickArtworkFile() async => filePath;
}

class _FakeArtworkAssetRepository implements ArtworkAssetRepository {
  final Map<String, ArtworkAsset> _assets = {};
  final List<ArtworkAsset> createdAssets = [];

  @override
  Future<void> create(ArtworkAsset artworkAsset) async {
    createdAssets.add(artworkAsset);
    _assets[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<void> save(ArtworkAsset artworkAsset) async {
    _assets[artworkAsset.id] = artworkAsset;
  }

  @override
  Future<ArtworkAsset?> getById(String id) async => _assets[id];

  @override
  Future<ArtworkAsset?> getByNormalizedPath(String normalizedPath) async {
    for (final asset in _assets.values) {
      if (asset.normalizedPath == normalizedPath) {
        return asset;
      }
    }

    return null;
  }

  @override
  Future<List<ArtworkAsset>> getAll() async =>
      List<ArtworkAsset>.unmodifiable(_assets.values);
}

class _FakeSongRepository implements SongRepository {
  _FakeSongRepository(List<Song> songs)
    : _songs = {for (final song in songs) song.id: song};

  final Map<String, Song> _songs;

  @override
  Future<void> create(Song song) async {
    _songs[song.id] = song;
  }

  @override
  Future<void> save(Song song) async {
    _songs[song.id] = song;
  }

  @override
  Future<Song?> getById(String id) async => _songs[id];

  @override
  Future<List<Song>> getAll() async => List<Song>.unmodifiable(_songs.values);

  @override
  Future<List<Song>> getByArtistId(String artistId) async => _songs.values
      .where((song) => song.artistId == artistId)
      .toList(growable: false);

  @override
  Future<List<Song>> getByAlbumId(String albumId) async => _songs.values
      .where((song) => song.albumId == albumId)
      .toList(growable: false);

  @override
  Future<List<Song>> getByEditionId(String albumEditionId) async => _songs
      .values
      .where((song) => song.albumEditionId == albumEditionId)
      .toList(growable: false);

  @override
  Future<List<Song>> getRecentlyAdded(int limit) async =>
      _songs.values.take(limit).toList(growable: false);
}

class _FakeArtistRepository implements ArtistRepository {
  @override
  Future<void> create(Artist artist) async {}

  @override
  Future<void> save(Artist artist) async {}

  @override
  Future<Artist?> getById(String id) async => null;

  @override
  Future<List<Artist>> getAll() async => const [];
}

class _FakeAlbumEditionRepository implements AlbumEditionRepository {
  _FakeAlbumEditionRepository([List<AlbumEdition> editions = const []])
    : _editions = {for (final edition in editions) edition.id: edition};

  final Map<String, AlbumEdition> _editions;
  final List<AlbumEdition> savedEditions = [];

  @override
  Future<void> create(AlbumEdition edition) async {
    _editions[edition.id] = edition;
  }

  @override
  Future<void> save(AlbumEdition edition) async {
    savedEditions.add(edition);
    _editions[edition.id] = edition;
  }

  @override
  Future<AlbumEdition?> getById(String id) async => _editions[id];

  @override
  Future<List<AlbumEdition>> getAll() async =>
      List<AlbumEdition>.unmodifiable(_editions.values);

  @override
  Future<List<AlbumEdition>> getByAlbumId(String albumId) async => _editions
      .values
      .where((edition) => edition.albumId == albumId)
      .toList(growable: false);
}

class _FakeAlbumProfileEditingService extends AlbumProfileEditingService {
  _FakeAlbumProfileEditingService()
    : super(mutationRunner: _UnusedMutationRunner());

  int updateCallCount = 0;
  String? lastAlbumId;
  String? lastPrimaryEditionId;
  String? lastTitle;

  @override
  Future<AlbumProfileEditResult> updateProfile({
    required String userId,
    required String albumId,
    required String primaryEditionId,
    required String title,
    required String editionTitle,
    required AlbumEditionType editionType,
    required DateTime? releaseDate,
    required String? genre,
    String? artistId,
    DateTime? now,
  }) async {
    updateCallCount++;
    lastAlbumId = albumId;
    lastPrimaryEditionId = primaryEditionId;
    lastTitle = title;

    final timestamp = now ?? DateTime.utc(2026, 9, 17, 13);

    return AlbumProfileEditResult(
      album: Album(
        id: albumId,
        artistId: artistId ?? 'artist-song-1',
        title: title,
        canonicalTitle: title.trim().toLowerCase(),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      primaryEdition: AlbumEdition(
        id: primaryEditionId,
        albumId: albumId,
        title: editionTitle,
        type: editionType,
        isPrimary: true,
        releaseDate: releaseDate,
        genre: genre,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      albumChanged: true,
      primaryEditionChanged: true,
    );
  }
}

class _FakeArtistCreationService extends ArtistCreationService {
  _FakeArtistCreationService({required this.libraryRepository})
    : super(mutationRunner: _UnusedMutationRunner());

  final _FakeLibraryRepository libraryRepository;

  String? lastRequestedUserId;
  String? lastRequestedName;

  @override
  Future<Artist> createOrReuse({
    required String userId,
    required String name,
    DateTime? now,
  }) async {
    lastRequestedUserId = userId;
    lastRequestedName = name;

    final canonicalName = name.trim().toLowerCase();

    for (final libraryArtist in libraryRepository.artists) {
      if (libraryArtist.name.trim().toLowerCase() == canonicalName) {
        return Artist(
          id: libraryArtist.artistId,
          name: libraryArtist.name,
          canonicalName: canonicalName,
          createdAt: DateTime.utc(2026, 9, 17, 13),
          updatedAt: DateTime.utc(2026, 9, 17, 13),
        );
      }
    }

    const artistId = 'artist-created';
    final timestamp = DateTime.utc(2026, 9, 17, 13);

    final artist = Artist(
      id: artistId,
      name: name,
      canonicalName: canonicalName,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    libraryRepository.artists.add(
      LibraryArtist(
        artistId: artistId,
        name: name,
        albumCount: 0,
        songCount: 0,
        dateAdded: timestamp,
      ),
    );

    return artist;
  }
}

class _UnusedMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Unused fake mutation runner.');
  }
}
