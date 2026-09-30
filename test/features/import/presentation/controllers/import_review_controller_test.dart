import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/artwork/domain/repositories/artwork_asset_repository.dart';

import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/import/presentation/controllers/import_review_controller.dart';
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
      featuredArtists: const [],
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

  ImportReviewController buildController({
    required List<SongImportReview> reviews,
    required Map<String, LibraryTrack> tracks,
    String? userId = 'user-1',
    Object? editError,
    Object? reviewSaveError,
    ArtworkAssignmentService? artworkAssignmentService,
    ArtworkFilePicker? artworkFilePicker,
    List<LibraryAlbum> albums = const [],
    List<LibraryArtist> artists = const [],
    AlbumProfileEditingService? albumProfileEditingService,
    ArtistCreationService? artistCreationService,
  }) {
    final reviewRepository = _FakeReviewRepository(
      reviews,
      saveError: reviewSaveError,
    );
    final libraryRepository = _FakeLibraryRepository(
      tracks,
      albums: albums,
      artists: artists,
    );
    final editingService = _FakeEditingService(
      error: editError,
      libraryRepository: libraryRepository,
    );

    return ImportReviewController(
      service: ImportReviewService(
        reviewRepository: reviewRepository,
        libraryQueryRepository: libraryRepository,
        trackProfileEditingService: editingService,
        artistCreationService:
            artistCreationService ??
            _FakeArtistCreationService(libraryRepository: libraryRepository),
        now: () => DateTime.utc(2026, 9, 17, 13),
      ),
      userId: userId,
      artworkAssignmentService: artworkAssignmentService,
      artworkFilePicker: artworkFilePicker,
      albumProfileEditingService: albumProfileEditingService,
    );
  }

  test('load exposes first unresolved review and remaining count', () async {
    final controller = buildController(
      reviews: [review('song-1'), review('song-2')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      },
    );

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.remainingCount, 2);
    expect(controller.currentItem, isNotNull);
    expect(controller.currentItem!.track.songId, 'song-1');
    expect(controller.currentItem!.track.title, 'First Song');
    expect(controller.isComplete, isFalse);

    controller.dispose();
  });

  test('navigation changes current review without resolving it', () async {
    final controller = buildController(
      reviews: [review('song-1'), review('song-2'), review('song-3')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
        'song-3': track('song-3', 'Third Song'),
      },
    );

    await controller.load();

    expect(controller.currentPosition, 1);
    expect(controller.currentItem!.track.songId, 'song-1');
    expect(controller.canGoPrevious, isFalse);
    expect(controller.canGoNext, isTrue);
    expect(controller.remainingCount, 3);

    controller.goNext();

    expect(controller.currentPosition, 2);
    expect(controller.currentItem!.track.songId, 'song-2');
    expect(controller.canGoPrevious, isTrue);
    expect(controller.canGoNext, isTrue);
    expect(controller.remainingCount, 3);

    controller.goPrevious();

    expect(controller.currentPosition, 1);
    expect(controller.currentItem!.track.songId, 'song-1');
    expect(controller.remainingCount, 3);

    controller.dispose();
  });

  test('navigation stops at queue boundaries', () async {
    final controller = buildController(
      reviews: [review('song-1'), review('song-2')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      },
    );

    await controller.load();

    controller.goPrevious();

    expect(controller.currentPosition, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    controller.goNext();
    controller.goNext();

    expect(controller.currentPosition, 2);
    expect(controller.currentItem!.track.songId, 'song-2');
    expect(controller.canGoNext, isFalse);
    expect(controller.remainingCount, 2);

    controller.dispose();
  });

  test(
    'resolving a navigated review stays at its former queue position',
    () async {
      final controller = buildController(
        reviews: [review('song-1'), review('song-2'), review('song-3')],
        tracks: {
          'song-1': track('song-1', 'First Song'),
          'song-2': track('song-2', 'Second Song'),
          'song-3': track('song-3', 'Third Song'),
        },
      );

      await controller.load();
      controller.goNext();

      expect(controller.currentPosition, 2);
      expect(controller.currentItem!.track.songId, 'song-2');

      final result = await controller.resolveCurrent(
        title: 'Corrected Second Song',
        trackNumber: 2,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        artistId: 'artist-song-2',
        albumId: 'album-song-2',
        albumEditionId: 'edition-song-2',
      );

      expect(result, isTrue);
      expect(controller.remainingCount, 2);
      expect(controller.currentPosition, 2);
      expect(controller.currentItem!.track.songId, 'song-3');
      expect(controller.items.map((item) => item.track.songId), [
        'song-1',
        'song-3',
      ]);

      controller.dispose();
    },
  );

  test('failed resolve after navigation preserves selected review', () async {
    final controller = buildController(
      reviews: [review('song-1'), review('song-2'), review('song-3')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
        'song-3': track('song-3', 'Third Song'),
      },
      editError: StateError('edit failed'),
    );

    await controller.load();
    controller.goNext();

    final result = await controller.resolveCurrent(
      title: 'Corrected Second Song',
      trackNumber: 2,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-song-2',
      albumId: 'album-song-2',
      albumEditionId: 'edition-song-2',
    );

    expect(result, isFalse);
    expect(controller.hasError, isTrue);
    expect(controller.remainingCount, 3);
    expect(controller.currentPosition, 2);
    expect(controller.currentItem!.track.songId, 'song-2');

    controller.dispose();
  });
  test('empty unresolved queue is complete after load', () async {
    final controller = buildController(reviews: const [], tracks: const {});

    await controller.load();

    expect(controller.items, isEmpty);
    expect(controller.currentItem, isNull);
    expect(controller.remainingCount, 0);
    expect(controller.isComplete, isTrue);
    expect(controller.hasError, isFalse);

    controller.dispose();
  });

  test('successful resolve advances to next review', () async {
    final controller = buildController(
      reviews: [review('song-1'), review('song-2')],
      tracks: {
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      },
    );

    await controller.load();

    expect(controller.currentItem!.track.songId, 'song-1');

    final result = await controller.resolveCurrent(
      title: 'Corrected First Song',
      trackNumber: 1,
      discNumber: 7,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-song-1',
      albumId: 'album-song-1',
      albumEditionId: 'edition-song-1',
    );

    expect(result, isTrue);
    expect(controller.hasError, isFalse);
    expect(controller.remainingCount, 1);
    expect(controller.currentItem, isNotNull);
    expect(controller.currentItem!.track.songId, 'song-2');
    expect(controller.isComplete, isFalse);

    controller.dispose();
  });

  test('resolving final review produces complete state', () async {
    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Only Song')},
    );

    await controller.load();

    final result = await controller.resolveCurrent(
      title: 'Corrected Song',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-song-1',
      albumId: 'album-song-1',
      albumEditionId: 'edition-song-1',
    );

    expect(result, isTrue);
    expect(controller.remainingCount, 0);
    expect(controller.currentItem, isNull);
    expect(controller.isComplete, isTrue);

    controller.dispose();
  });

  test('failed resolve preserves current review and exposes error', () async {
    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      editError: StateError('edit failed'),
    );

    await controller.load();

    final result = await controller.resolveCurrent(
      title: 'Corrected Song',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-song-1',
      albumId: 'album-song-1',
      albumEditionId: 'edition-song-1',
    );

    expect(result, isFalse);
    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
    expect(controller.remainingCount, 1);
    expect(controller.currentItem, isNotNull);
    expect(controller.currentItem!.track.songId, 'song-1');
    expect(controller.isComplete, isFalse);

    controller.dispose();
  });

  test(
    'review save failure reloads persisted track metadata while preserving error',
    () async {
      final controller = buildController(
        reviews: [review('song-1')],
        tracks: {'song-1': track('song-1', 'Original Title')},
        reviewSaveError: StateError('review save failed'),
      );

      await controller.load();

      expect(controller.currentItem!.track.title, 'Original Title');

      final result = await controller.resolveCurrent(
        title: 'Persisted Corrected Title',
        trackNumber: 7,
        discNumber: 8,
        featuredArtists: const ['Guest'],
        isSingle: true,
        artistId: 'artist-song-1',
        albumId: 'album-song-1',
        albumEditionId: 'edition-song-1',
      );

      expect(result, isFalse);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());

      expect(controller.remainingCount, 1);
      expect(controller.currentItem, isNotNull);
      expect(controller.currentItem!.track.songId, 'song-1');
      expect(controller.currentItem!.track.title, 'Persisted Corrected Title');
      expect(controller.currentItem!.track.trackNumber, 7);
      expect(controller.currentItem!.track.discNumber, 8);
      expect(controller.currentItem!.track.featuredArtists, ['Guest']);
      expect(controller.currentItem!.track.isSingle, isTrue);
      expect(controller.isComplete, isFalse);

      controller.dispose();
    },
  );
  test('changing artwork keeps import review unresolved', () async {
    final songRepository = _FakeSongRepository([
      _songForArtwork('song-1', artworkId: 'artwork-old'),
    ]);

    final artworkRepository = _FakeArtworkAssetRepository();

    final controller = buildController(
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

    await controller.load();

    expect(controller.canEditArtwork, isTrue);
    expect(controller.remainingCount, 1);

    final changed = await controller.changeCurrentArtwork();

    expect(changed, isTrue);
    expect(controller.isUpdatingArtwork, isFalse);
    expect(controller.remainingCount, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    final savedSong = await songRepository.getById('song-1');

    expect(savedSong, isNotNull);
    expect(savedSong!.artworkId, isNot('artwork-old'));
    expect(artworkRepository.createdAssets, hasLength(1));

    controller.dispose();
  });

  test('clearing artwork keeps import review unresolved', () async {
    final songRepository = _FakeSongRepository([
      _songForArtwork('song-1', artworkId: 'artwork-existing'),
    ]);

    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      artworkAssignmentService: _artworkService(songRepository: songRepository),
      artworkFilePicker: const _FakeArtworkFilePicker(
        filePath: r'C:\Artwork\Unused.jpg',
      ),
    );

    await controller.load();

    expect(controller.canEditArtwork, isTrue);

    final changed = await controller.clearCurrentArtwork();

    expect(changed, isTrue);
    expect(controller.isUpdatingArtwork, isFalse);
    expect(controller.remainingCount, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    final savedSong = await songRepository.getById('song-1');

    expect(savedSong, isNotNull);
    expect(savedSong!.artworkId, isNull);

    controller.dispose();
  });

  test('cancelled artwork picker does not mutate song or review', () async {
    final songRepository = _FakeSongRepository([
      _songForArtwork('song-1', artworkId: 'artwork-existing'),
    ]);

    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      artworkAssignmentService: _artworkService(songRepository: songRepository),
      artworkFilePicker: const _FakeArtworkFilePicker(),
    );

    await controller.load();

    final changed = await controller.changeCurrentArtwork();

    expect(changed, isFalse);
    expect(controller.remainingCount, 1);

    final savedSong = await songRepository.getById('song-1');

    expect(savedSong!.artworkId, 'artwork-existing');
    expect(songRepository.savedSongs, isEmpty);

    controller.dispose();
  });
  test('changing album artwork keeps import review unresolved', () async {
    final songRepository = _FakeSongRepository([_songForArtwork('song-1')]);
    final albumEditionRepository = _FakeAlbumEditionRepository([
      _albumEditionForArtwork('song-1', artworkId: 'album-artwork-old'),
    ]);
    final artworkRepository = _FakeArtworkAssetRepository();

    final controller = buildController(
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

    await controller.load();

    expect(controller.canEditAlbumArtwork, isTrue);
    expect(controller.remainingCount, 1);

    final changed = await controller.changeCurrentAlbumArtwork();

    expect(changed, isTrue);
    expect(controller.isUpdatingAlbumArtwork, isFalse);
    expect(controller.remainingCount, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    final savedEdition = await albumEditionRepository.getById('edition-song-1');

    expect(savedEdition, isNotNull);
    expect(savedEdition!.artworkId, isNot('album-artwork-old'));
    expect(albumEditionRepository.savedEditions, hasLength(1));
    expect(artworkRepository.createdAssets, hasLength(1));

    controller.dispose();
  });

  test('clearing album artwork keeps import review unresolved', () async {
    final songRepository = _FakeSongRepository([_songForArtwork('song-1')]);
    final albumEditionRepository = _FakeAlbumEditionRepository([
      _albumEditionForArtwork('song-1', artworkId: 'album-artwork-existing'),
    ]);

    final controller = buildController(
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

    await controller.load();

    expect(controller.canEditAlbumArtwork, isTrue);

    final changed = await controller.clearCurrentAlbumArtwork();

    expect(changed, isTrue);
    expect(controller.isUpdatingAlbumArtwork, isFalse);
    expect(controller.remainingCount, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    final savedEdition = await albumEditionRepository.getById('edition-song-1');

    expect(savedEdition, isNotNull);
    expect(savedEdition!.artworkId, isNull);
    expect(albumEditionRepository.savedEditions, hasLength(1));

    controller.dispose();
  });
  test('editing album keeps import review unresolved', () async {
    final albumEditingService = _FakeAlbumProfileEditingService();

    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      albums: [albumForSong('song-1')],
      albumProfileEditingService: albumEditingService,
    );

    await controller.load();

    expect(controller.canEditAlbum, isTrue);
    expect(controller.currentAlbum, isNotNull);
    expect(controller.remainingCount, 1);

    final releaseDate = DateTime.utc(2025, 6, 20);

    final changed = await controller.updateCurrentAlbum(
      title: 'Corrected Album',
      artistId: 'artist-song-1',
      editionTitle: 'Deluxe Edition',
      editionType: AlbumEditionType.deluxe,
      releaseDate: releaseDate,
      genre: 'Alternative',
    );

    expect(changed, isTrue);
    expect(controller.isUpdatingAlbum, isFalse);

    expect(albumEditingService.updateCallCount, 1);
    expect(albumEditingService.lastUserId, 'user-1');
    expect(albumEditingService.lastAlbumId, 'album-song-1');
    expect(albumEditingService.lastPrimaryEditionId, 'edition-song-1');
    expect(albumEditingService.lastTitle, 'Corrected Album');
    expect(albumEditingService.lastArtistId, 'artist-song-1');
    expect(albumEditingService.lastEditionTitle, 'Deluxe Edition');
    expect(albumEditingService.lastEditionType, AlbumEditionType.deluxe);
    expect(albumEditingService.lastReleaseDate, releaseDate);
    expect(albumEditingService.lastGenre, 'Alternative');

    expect(controller.remainingCount, 1);
    expect(controller.currentItem, isNotNull);
    expect(controller.currentItem!.track.songId, 'song-1');
    expect(controller.isComplete, isFalse);

    controller.dispose();
  });
  test(
    'creating artist refreshes artists without moving current review',
    () async {
      final tracks = <String, LibraryTrack>{
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
        'song-3': track('song-3', 'Third Song'),
      };

      final reviews = <SongImportReview>[
        review('song-1'),
        review('song-2'),
        review('song-3'),
      ];

      final libraryRepository = _FakeLibraryRepository(tracks);
      final artistCreationService = _FakeArtistCreationService(
        libraryRepository: libraryRepository,
      );

      final controller = ImportReviewController(
        service: ImportReviewService(
          reviewRepository: _FakeReviewRepository(reviews),
          libraryQueryRepository: libraryRepository,
          trackProfileEditingService: _FakeEditingService(
            libraryRepository: libraryRepository,
          ),
          artistCreationService: artistCreationService,
        ),
        userId: 'user-1',
      );

      await controller.load();
      controller.goNext();

      expect(controller.currentPosition, 2);
      expect(controller.currentItem!.track.songId, 'song-2');
      expect(controller.artists, isEmpty);

      final created = await controller.createOrReuseArtist('Victoria Justice');

      expect(created, isNotNull);
      expect(created!.artistId, 'artist-created');
      expect(created.name, 'Victoria Justice');

      expect(artistCreationService.callCount, 1);
      expect(artistCreationService.lastUserId, 'user-1');
      expect(artistCreationService.lastName, 'Victoria Justice');

      expect(controller.isCreatingArtist, isFalse);
      expect(controller.isBusy, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.artists, hasLength(1));
      expect(controller.artists.single.artistId, 'artist-created');

      expect(controller.remainingCount, 3);
      expect(controller.currentPosition, 2);
      expect(controller.currentItem!.track.songId, 'song-2');

      controller.dispose();
    },
  );

  test(
    'failed artist creation preserves current review and exposes error',
    () async {
      final tracks = <String, LibraryTrack>{
        'song-1': track('song-1', 'First Song'),
        'song-2': track('song-2', 'Second Song'),
      };

      final libraryRepository = _FakeLibraryRepository(tracks);
      final artistCreationService = _FakeArtistCreationService(
        libraryRepository: libraryRepository,
        error: StateError('artist creation failed'),
      );

      final controller = ImportReviewController(
        service: ImportReviewService(
          reviewRepository: _FakeReviewRepository([
            review('song-1'),
            review('song-2'),
          ]),
          libraryQueryRepository: libraryRepository,
          trackProfileEditingService: _FakeEditingService(
            libraryRepository: libraryRepository,
          ),
          artistCreationService: artistCreationService,
        ),
        userId: 'user-1',
      );

      await controller.load();
      controller.goNext();

      final created = await controller.createOrReuseArtist('Victoria Justice');

      expect(created, isNull);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isCreatingArtist, isFalse);
      expect(controller.isBusy, isFalse);

      expect(controller.remainingCount, 2);
      expect(controller.currentPosition, 2);
      expect(controller.currentItem!.track.songId, 'song-2');
      expect(controller.artists, isEmpty);

      controller.dispose();
    },
  );

  test('signed-out user can create artist', () async {
    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      userId: null,
    );

    await controller.load();

    final created = await controller.createOrReuseArtist('Victoria Justice');

    expect(created, isNotNull);
    expect(created!.artistId, 'artist-created');
    expect(created.name, 'Victoria Justice');

    expect(controller.hasError, isFalse);
    expect(controller.isCreatingArtist, isFalse);
    expect(controller.isBusy, isFalse);

    expect(controller.artists, hasLength(1));
    expect(controller.artists.single.artistId, 'artist-created');

    expect(controller.remainingCount, 1);
    expect(controller.currentItem!.track.songId, 'song-1');

    controller.dispose();
  });

  test('signed-out user can resolve current review', () async {
    final controller = buildController(
      reviews: [review('song-1')],
      tracks: {'song-1': track('song-1', 'Needs Review')},
      userId: null,
    );

    await controller.load();

    final result = await controller.resolveCurrent(
      title: 'Corrected Song',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-song-1',
      albumId: 'album-song-1',
      albumEditionId: 'edition-song-1',
    );

    expect(result, isTrue);
    expect(controller.hasError, isFalse);
    expect(controller.remainingCount, 0);
    expect(controller.currentItem, isNull);
    expect(controller.isComplete, isTrue);

    controller.dispose();
  });

  test('load failure exposes error without reporting completion', () async {
    final controller = ImportReviewController(
      service: ImportReviewService(
        reviewRepository: _FakeReviewRepository([review('missing-song')]),
        libraryQueryRepository: _FakeLibraryRepository(const {}),
        trackProfileEditingService: _FakeEditingService(
          libraryRepository: _FakeLibraryRepository(const {}),
        ),
        artistCreationService: _FakeArtistCreationService(),
      ),
      userId: 'user-1',
    );

    await controller.load();

    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
    expect(controller.isLoading, isFalse);
    expect(controller.currentItem, isNull);
    expect(controller.isComplete, isFalse);

    controller.dispose();
  });
}

class _FakeReviewRepository implements SongImportReviewRepository {
  _FakeReviewRepository(List<SongImportReview> reviews, {this.saveError})
    : _reviews = {for (final review in reviews) review.songId: review};

  final Map<String, SongImportReview> _reviews;
  final Object? saveError;

  @override
  Future<void> create(SongImportReview review) async {
    _reviews[review.songId] = review;
  }

  @override
  Future<void> save(SongImportReview review) async {
    final failure = saveError;

    if (failure != null) {
      throw failure;
    }

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
    Map<String, LibraryTrack> tracks, {
    this.albums = const [],
    List<LibraryArtist> artists = const [],
  }) : tracks = Map<String, LibraryTrack>.from(tracks),
       artists = List<LibraryArtist>.from(artists);

  final Map<String, LibraryTrack> tracks;
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;

  void saveTrack(LibraryTrack track) {
    tracks[track.songId] = track;
  }

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
  Future<LibraryArtist?> getArtistById(String artistId) async => null;
}

class _FakeEditingService extends TrackProfileEditingService {
  _FakeEditingService({this.error, required this._libraryRepository})
    : super(mutationRunner: _UnusedMutationRunner());

  final Object? error;
  final _FakeLibraryRepository _libraryRepository;

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String? userId,
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
    final failure = error;

    if (failure != null) {
      throw failure;
    }

    final timestamp = now ?? DateTime.utc(2026, 9, 17, 13);

    final song = Song(
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
    );

    final previousTrack = await _libraryRepository.getTrackById(songId);

    if (previousTrack != null) {
      _libraryRepository.saveTrack(
        LibraryTrack(
          songId: song.id,
          title: song.title,
          artistId: song.artistId,
          artistName: previousTrack.artistName,
          albumId: song.albumId,
          albumTitle: previousTrack.albumTitle,
          albumEditionId: song.albumEditionId,
          albumEditionTitle: previousTrack.albumEditionTitle,
          albumEditionType: previousTrack.albumEditionType,
          trackNumber: song.trackNumber,
          discNumber: song.discNumber,
          durationSeconds: previousTrack.durationSeconds,
          isSingle: song.isSingle,
          featuredArtists: song.featuredArtists,
          dateAdded: previousTrack.dateAdded,
          filePath: previousTrack.filePath,
          isAvailable: previousTrack.isAvailable,
        ),
      );
    }

    return TrackProfileEditResult(song: song, changed: true);
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
  final List<Song> savedSongs = [];

  @override
  Future<void> create(Song song) async {
    _songs[song.id] = song;
  }

  @override
  Future<void> save(Song song) async {
    savedSongs.add(song);
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

  @override
  Future<void> delete(String id) async {}
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

  String? lastUserId;
  String? lastAlbumId;
  String? lastPrimaryEditionId;
  String? lastTitle;
  String? lastArtistId;
  String? lastEditionTitle;
  AlbumEditionType? lastEditionType;
  DateTime? lastReleaseDate;
  String? lastGenre;

  @override
  Future<AlbumProfileEditResult> updateProfile({
    required String? userId,
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

    lastUserId = userId;
    lastAlbumId = albumId;
    lastPrimaryEditionId = primaryEditionId;
    lastTitle = title;
    lastArtistId = artistId;
    lastEditionTitle = editionTitle;
    lastEditionType = editionType;
    lastReleaseDate = releaseDate;
    lastGenre = genre;

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
  _FakeArtistCreationService({this.libraryRepository, this.error})
    : super(mutationRunner: _UnusedMutationRunner());

  final _FakeLibraryRepository? libraryRepository;
  final Object? error;

  int callCount = 0;
  String? lastUserId;
  String? lastName;

  @override
  Future<Artist> createOrReuse({
    required String? userId,
    required String name,
    DateTime? now,
  }) async {
    callCount++;
    lastUserId = userId;
    lastName = name;

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    final timestamp = now ?? DateTime.utc(2026, 9, 17, 13);

    final artist = Artist(
      id: 'artist-created',
      name: name.trim(),
      canonicalName: name.trim().toLowerCase(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    libraryRepository?.artists.add(
      LibraryArtist(
        artistId: artist.id,
        name: artist.name,
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
