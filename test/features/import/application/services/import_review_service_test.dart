import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/models/import_review_queue_item.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 17, 12);
  final resolvedAt = DateTime.utc(2026, 9, 17, 13);

  LibraryTrack track({
    String songId = 'song-1',
    String title = 'Imported Song',
  }) {
    return LibraryTrack(
      songId: songId,
      title: title,
      artistId: 'artist-1',
      artistName: 'Unknown Artist',
      albumId: 'album-1',
      albumTitle: 'Unknown Album',
      albumEditionId: 'edition-1',
      albumEditionTitle: 'Unknown Album',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 0,
      durationSeconds: 0,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: createdAt,
      filePath: r'C:\Music\Imported Song.mp3',
      isAvailable: true,
    );
  }

  SongImportReview review({String songId = 'song-1', DateTime? resolvedAt}) {
    return SongImportReview(
      songId: songId,
      metadataSource: MetadataSource.fallback,
      reasons: const [
        ImportReviewReason.fallbackMetadata,
        ImportReviewReason.unknownArtist,
        ImportReviewReason.unknownAlbum,
      ],
      resolvedAt: resolvedAt,
      createdAt: createdAt,
      updatedAt: resolvedAt ?? createdAt,
    );
  }

  test(
    'loads unresolved reviews joined to library tracks in review order',
    () async {
      final reviewRepository = _FakeReviewRepository(
        reviews: [
          review(songId: 'song-1'),
          review(songId: 'song-2'),
        ],
      );

      final libraryRepository = _FakeLibraryQueryRepository(
        tracks: {
          'song-1': track(songId: 'song-1', title: 'First'),
          'song-2': track(songId: 'song-2', title: 'Second'),
        },
      );

      final service = ImportReviewService(
        reviewRepository: reviewRepository,
        libraryQueryRepository: libraryRepository,
        trackProfileEditingService: _FakeTrackProfileEditingService(),
        artistCreationService: _FakeArtistCreationService(),
        now: () => resolvedAt,
      );

      final items = await service.getUnresolved();

      expect(items, hasLength(2));
      expect(items[0].review.songId, 'song-1');
      expect(items[0].track.title, 'First');
      expect(items[1].review.songId, 'song-2');
      expect(items[1].track.title, 'Second');
    },
  );

  test('fails when review points to a missing library track', () async {
    final service = ImportReviewService(
      reviewRepository: _FakeReviewRepository(
        reviews: [review(songId: 'missing-song')],
      ),
      libraryQueryRepository: _FakeLibraryQueryRepository(),
      trackProfileEditingService: _FakeTrackProfileEditingService(),
      artistCreationService: _FakeArtistCreationService(),
    );

    await expectLater(
      service.getUnresolved(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Track not found for import review: missing-song',
        ),
      ),
    );
  });

  test(
    'createOrReuseArtist delegates creation and returns query artist',
    () async {
      final domainArtist = Artist(
        id: 'artist-victoria',
        name: 'Victoria Justice',
        canonicalName: 'victoria justice',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final libraryArtist = LibraryArtist(
        artistId: domainArtist.id,
        name: domainArtist.name,
        albumCount: 0,
        songCount: 0,
        dateAdded: createdAt,
      );

      final artistCreationService = _FakeArtistCreationService(
        result: domainArtist,
      );

      final service = ImportReviewService(
        reviewRepository: _FakeReviewRepository(),
        libraryQueryRepository: _FakeLibraryQueryRepository(
          artists: [libraryArtist],
        ),
        trackProfileEditingService: _FakeTrackProfileEditingService(),
        artistCreationService: artistCreationService,
      );

      final result = await service.createOrReuseArtist(
        userId: 'user-1',
        name: 'Victoria Justice',
      );

      expect(artistCreationService.callCount, 1);
      expect(artistCreationService.lastUserId, 'user-1');
      expect(artistCreationService.lastName, 'Victoria Justice');

      expect(result.artistId, 'artist-victoria');
      expect(result.name, 'Victoria Justice');
      expect(result, same(libraryArtist));
    },
  );

  test(
    'createOrReuseArtist fails when created artist is absent from query projection',
    () async {
      final domainArtist = Artist(
        id: 'artist-missing',
        name: 'Missing Artist',
        canonicalName: 'missing artist',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final service = ImportReviewService(
        reviewRepository: _FakeReviewRepository(),
        libraryQueryRepository: _FakeLibraryQueryRepository(),
        trackProfileEditingService: _FakeTrackProfileEditingService(),
        artistCreationService: _FakeArtistCreationService(result: domainArtist),
      );

      await expectLater(
        service.createOrReuseArtist(userId: 'user-1', name: 'Missing Artist'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Created artist not found in library query: artist-missing',
          ),
        ),
      );
    },
  );
  test('updates track before marking review resolved', () async {
    final originalReview = review();

    final reviewRepository = _FakeReviewRepository(reviews: [originalReview]);

    final editingService = _FakeTrackProfileEditingService();

    final service = ImportReviewService(
      reviewRepository: reviewRepository,
      libraryQueryRepository: _FakeLibraryQueryRepository(
        tracks: {'song-1': track()},
      ),
      trackProfileEditingService: editingService,
      artistCreationService: _FakeArtistCreationService(),
      now: () => resolvedAt,
    );

    final item = ImportReviewQueueItem(review: originalReview, track: track());

    final result = await service.updateTrackAndResolve(
      userId: ' user-1 ',
      item: item,
      title: 'Corrected Song',
      trackNumber: 4,
      discNumber: 6,
      featuredArtists: const ['Guest'],
      isSingle: true,
      artistId: 'artist-corrected',
      albumId: 'album-corrected',
      albumEditionId: 'edition-corrected',
    );

    expect(result.changed, isTrue);

    expect(editingService.updateCallCount, 1);
    expect(editingService.lastUserId, 'user-1');
    expect(editingService.lastSongId, 'song-1');
    expect(editingService.lastTitle, 'Corrected Song');
    expect(editingService.lastTrackNumber, 4);
    expect(editingService.lastDiscNumber, 6);
    expect(editingService.lastFeaturedArtists, ['Guest']);
    expect(editingService.lastIsSingle, isTrue);
    expect(editingService.lastArtistId, 'artist-corrected');
    expect(editingService.lastAlbumId, 'album-corrected');
    expect(editingService.lastAlbumEditionId, 'edition-corrected');

    expect(reviewRepository.saveCallCount, 1);

    expect(editingService.lastMetadataAuthority, MetadataAuthority.confirmed);
    expect(editingService.lastMetadataSource, MetadataProvenanceSource.review);

    final savedReview = reviewRepository.lastSaved;

    expect(savedReview, isNotNull);
    expect(savedReview!.songId, 'song-1');
    expect(savedReview.resolvedAt, resolvedAt);
    expect(savedReview.updatedAt, resolvedAt);
    expect(savedReview.metadataSource, MetadataSource.fallback);
    expect(savedReview.reasons, originalReview.reasons);
  });

  test('failed track edit leaves review unresolved', () async {
    final originalReview = review();

    final reviewRepository = _FakeReviewRepository(reviews: [originalReview]);

    final editingService = _FakeTrackProfileEditingService(
      updateError: StateError('edit failed'),
    );

    final service = ImportReviewService(
      reviewRepository: reviewRepository,
      libraryQueryRepository: _FakeLibraryQueryRepository(
        tracks: {'song-1': track()},
      ),
      trackProfileEditingService: editingService,
      artistCreationService: _FakeArtistCreationService(),
      now: () => resolvedAt,
    );

    final item = ImportReviewQueueItem(review: originalReview, track: track());

    await expectLater(
      service.updateTrackAndResolve(
        userId: 'user-1',
        item: item,
        title: 'Corrected',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        artistId: 'artist-1',
        albumId: 'album-1',
        albumEditionId: 'edition-1',
      ),
      throwsA(isA<StateError>()),
    );

    expect(editingService.updateCallCount, 1);
    expect(reviewRepository.saveCallCount, 0);

    final stored = await reviewRepository.getBySongId('song-1');

    expect(stored, isNotNull);
    expect(stored!.resolvedAt, isNull);
    expect(stored.needsReview, isTrue);
  });

  test(
    'resolution persistence failure happens after successful track edit',
    () async {
      final originalReview = review();

      final reviewRepository = _FakeReviewRepository(
        reviews: [originalReview],
        saveError: StateError('review save failed'),
      );

      final editingService = _FakeTrackProfileEditingService();

      final service = ImportReviewService(
        reviewRepository: reviewRepository,
        libraryQueryRepository: _FakeLibraryQueryRepository(
          tracks: {'song-1': track()},
        ),
        trackProfileEditingService: editingService,
        artistCreationService: _FakeArtistCreationService(),
        now: () => resolvedAt,
      );

      final item = ImportReviewQueueItem(
        review: originalReview,
        track: track(),
      );

      await expectLater(
        service.updateTrackAndResolve(
          userId: 'user-1',
          item: item,
          title: 'Corrected Song',
          trackNumber: 2,
          discNumber: 1,
          featuredArtists: const [],
          isSingle: false,
          artistId: 'artist-1',
          albumId: 'album-1',
          albumEditionId: 'edition-1',
        ),
        throwsA(isA<StateError>()),
      );

      expect(editingService.updateCallCount, 1);
      expect(reviewRepository.saveCallCount, 1);

      final stored = await reviewRepository.getBySongId('song-1');

      expect(stored, isNotNull);
      expect(stored!.resolvedAt, isNull);
      expect(stored.needsReview, isTrue);
    },
  );

  test('signed-out user can edit and resolve review', () async {
    final originalReview = review();

    final reviewRepository = _FakeReviewRepository(reviews: [originalReview]);

    final editingService = _FakeTrackProfileEditingService();

    final service = ImportReviewService(
      reviewRepository: reviewRepository,
      libraryQueryRepository: _FakeLibraryQueryRepository(
        tracks: {'song-1': track()},
      ),
      trackProfileEditingService: editingService,
      artistCreationService: _FakeArtistCreationService(),
      now: () => resolvedAt,
    );

    final result = await service.updateTrackAndResolve(
      userId: null,
      item: ImportReviewQueueItem(review: originalReview, track: track()),
      title: 'Corrected',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      artistId: 'artist-1',
      albumId: 'album-1',
      albumEditionId: 'edition-1',
    );

    expect(result.changed, isTrue);
    expect(editingService.updateCallCount, 1);
    expect(editingService.lastUserId, isNull);
    expect(reviewRepository.saveCallCount, 1);

    final stored = await reviewRepository.getBySongId('song-1');

    expect(stored, isNotNull);
    expect(stored!.needsReview, isFalse);
    expect(stored.resolvedAt, resolvedAt);
  });

  test('rejects an already resolved review', () async {
    final resolvedReview = review(resolvedAt: resolvedAt);

    final reviewRepository = _FakeReviewRepository(reviews: [resolvedReview]);

    final editingService = _FakeTrackProfileEditingService();

    final service = ImportReviewService(
      reviewRepository: reviewRepository,
      libraryQueryRepository: _FakeLibraryQueryRepository(
        tracks: {'song-1': track()},
      ),
      trackProfileEditingService: editingService,
      artistCreationService: _FakeArtistCreationService(),
    );

    await expectLater(
      service.updateTrackAndResolve(
        userId: 'user-1',
        item: ImportReviewQueueItem(review: resolvedReview, track: track()),
        title: 'Corrected',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        artistId: 'artist-1',
        albumId: 'album-1',
        albumEditionId: 'edition-1',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Import review is already resolved: song-1',
        ),
      ),
    );

    expect(editingService.updateCallCount, 0);
    expect(reviewRepository.saveCallCount, 0);
  });
}

class _FakeReviewRepository implements SongImportReviewRepository {
  _FakeReviewRepository({
    List<SongImportReview> reviews = const [],
    this.saveError,
  }) : _reviews = {for (final review in reviews) review.songId: review};

  final Map<String, SongImportReview> _reviews;
  final Object? saveError;

  int saveCallCount = 0;
  SongImportReview? lastSaved;

  @override
  Future<void> create(SongImportReview review) async {
    _reviews[review.songId] = review;
  }

  @override
  Future<void> save(SongImportReview review) async {
    saveCallCount++;

    final error = saveError;

    if (error != null) {
      throw error;
    }

    lastSaved = review;
    _reviews[review.songId] = review;
  }

  @override
  Future<SongImportReview?> getBySongId(String songId) async {
    return _reviews[songId];
  }

  @override
  Future<List<SongImportReview>> getUnresolved() async {
    return _reviews.values
        .where((review) => !review.isResolved)
        .toList(growable: false);
  }

  @override
  Future<int> countUnresolved() async {
    return _reviews.values.where((review) => !review.isResolved).length;
  }
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({
    Map<String, LibraryTrack> tracks = const {},
    List<LibraryArtist> artists = const [],
  }) : _tracks = Map<String, LibraryTrack>.from(tracks),
       _artists = List<LibraryArtist>.from(artists);

  final Map<String, LibraryTrack> _tracks;
  final List<LibraryArtist> _artists;

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    return _tracks[songId];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async => _artists;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => _tracks.values.toList(growable: false);

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

class _FakeTrackProfileEditingService extends TrackProfileEditingService {
  _FakeTrackProfileEditingService({this.updateError})
    : super(mutationRunner: _UnusedSyncMutationRunner());

  final Object? updateError;

  MetadataAuthority? lastMetadataAuthority;
  MetadataProvenanceSource? lastMetadataSource;

  @override
  TrackProfileEditingService withMetadataProvenance({
    required MetadataAuthority authority,
    required MetadataProvenanceSource source,
  }) {
    lastMetadataAuthority = authority;
    lastMetadataSource = source;
    return this;
  }

  int updateCallCount = 0;

  String? lastUserId;
  String? lastSongId;
  String? lastTitle;
  int? lastTrackNumber;
  int? lastDiscNumber;
  List<String>? lastFeaturedArtists;
  bool? lastIsSingle;
  String? lastArtistId;
  String? lastAlbumId;
  String? lastAlbumEditionId;

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
    updateCallCount++;

    lastUserId = userId;
    lastSongId = songId;
    lastTitle = title;
    lastTrackNumber = trackNumber;
    lastDiscNumber = discNumber;
    lastFeaturedArtists = List<String>.from(featuredArtists);
    lastIsSingle = isSingle;
    lastArtistId = artistId;
    lastAlbumId = albumId;
    lastAlbumEditionId = albumEditionId;

    final error = updateError;

    if (error != null) {
      throw error;
    }

    final timestamp = now ?? DateTime.utc(2026, 9, 17);

    return TrackProfileEditResult(
      song: Song(
        id: songId,
        artistId: artistId ?? 'artist-1',
        albumId: albumId ?? 'album-1',
        albumEditionId: albumEditionId ?? 'edition-1',
        title: title,
        canonicalTitle: title.toLowerCase(),
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

class _FakeArtistCreationService extends ArtistCreationService {
  _FakeArtistCreationService({Artist? result})
    : result =
          result ??
          Artist(
            id: 'artist-created',
            name: 'Created Artist',
            canonicalName: 'created artist',
            createdAt: DateTime.utc(2026, 9, 19, 12),
            updatedAt: DateTime.utc(2026, 9, 19, 12),
          ),
      super(mutationRunner: _UnusedSyncMutationRunner());

  final Artist result;

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

    return result;
  }
}

class _UnusedSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Unused fake mutation runner.');
  }
}
