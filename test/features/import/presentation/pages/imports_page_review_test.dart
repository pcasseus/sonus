import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/application/services/import_batch_runner.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/services/import_source_picker.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/entities/song_import_review.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
import 'package:sonus_next/features/import/domain/repositories/song_import_review_repository.dart';
import 'package:sonus_next/features/import/domain/services/import_candidate_discovery.dart';
import 'package:sonus_next/features/import/presentation/pages/imports_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 17, 12);

  LibraryTrack track(String id) {
    return LibraryTrack(
      songId: id,
      title: 'Imported Song',
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

  SongImportReview review(String id) {
    return SongImportReview(
      songId: id,
      metadataSource: MetadataSource.fallback,
      reasons: const [ImportReviewReason.fallbackMetadata],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  testWidgets('idle imports page shows persistent needs-review entry', (
    tester,
  ) async {
    final reviewRepository = _FakeReviewRepository([
      review('song-1'),
      review('song-2'),
    ]);

    await tester.pumpWidget(
      _buildApp(
        reviewRepository: reviewRepository,
        tracks: {'song-1': track('song-1'), 'song-2': track('song-2')},
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('import-needs-review-card')),
      findsOneWidget,
    );
    expect(find.text('2 songs need review'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('open-import-review-button')),
      findsOneWidget,
    );
  });

  testWidgets('completed import shows needs-review count and review action', (
    tester,
  ) async {
    final reviewRepository = _FakeReviewRepository([review('song-1')]);

    await tester.pumpWidget(
      _buildApp(
        reviewRepository: reviewRepository,
        tracks: {'song-1': track('song-1')},
        sourcePicker: _FakeSourcePicker(
          filePath: r'C:\Music\Artist\Album\Song.mp3',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose MP3'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('import-result-card')),
      findsOneWidget,
    );
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('import-review-button')),
      findsOneWidget,
    );
    expect(find.text('Review metadata'), findsOneWidget);
  });

  testWidgets('returning from review refreshes persistent unresolved count', (
    tester,
  ) async {
    final reviewRepository = _FakeReviewRepository([review('song-1')]);

    await tester.pumpWidget(
      _buildApp(
        reviewRepository: reviewRepository,
        tracks: {'song-1': track('song-1')},
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1 song needs review'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('open-import-review-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('import-review-page')),
      findsOneWidget,
    );

    final stored = await reviewRepository.getBySongId('song-1');

    expect(stored, isNotNull);

    await reviewRepository.save(
      stored!.copyWith(
        resolvedAt: DateTime.utc(2026, 9, 17, 13),
        updatedAt: DateTime.utc(2026, 9, 17, 13),
      ),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('import-needs-review-card')),
      findsNothing,
    );
    expect(find.text('1 song needs review'), findsNothing);
  });
}

Widget _buildApp({
  required _FakeReviewRepository reviewRepository,
  required Map<String, LibraryTrack> tracks,
  ImportSourcePicker? sourcePicker,
}) {
  final workflowService = ImportWorkflowService(
    candidateDiscovery: const _FakeDiscovery(),
    batchRunner: const _FakeBatchRunner(),
    batchIdFactory: () => 'import-review-page-test',
  );

  final reviewService = ImportReviewService(
    reviewRepository: reviewRepository,
    libraryQueryRepository: _FakeLibraryRepository(tracks),
    trackProfileEditingService: _FakeEditingService(),
    artistCreationService: _FakeArtistCreationService(),
  );

  final accountController = AccountController(
    repository: const _FakeAccountRepository(),
  );

  return MultiProvider(
    providers: [
      Provider<ImportWorkflowService?>.value(value: workflowService),
      Provider<ImportReviewService?>.value(value: reviewService),
      ChangeNotifierProvider<AccountController>.value(value: accountController),
      Provider<ImportSourcePicker>.value(
        value: sourcePicker ?? const _FakeSourcePicker(),
      ),
    ],
    child: const MaterialApp(home: ImportsPage()),
  );
}

class _FakeAccountRepository implements AccountRepository {
  const _FakeAccountRepository();

  static const _user = AccountUser(id: 'user-1', email: 'test@example.com');

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  Future<AccountUser?> signInWithGoogle() async => _user;

  @override
  Future<void> signOut() async {}
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
  const _FakeLibraryRepository(this.tracks);

  final Map<String, LibraryTrack> tracks;

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => tracks[songId];

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

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
  _FakeEditingService() : super(mutationRunner: _UnusedMutationRunner());

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String? userId,
    required String songId,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) async {
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

class _FakeSourcePicker implements ImportSourcePicker {
  const _FakeSourcePicker({this.filePath});

  final String? filePath;

  @override
  Future<String?> pickSongFile() async => filePath;

  @override
  Future<String?> pickStructuredFolder() async => null;
}

class _FakeDiscovery implements ImportCandidateDiscovery {
  const _FakeDiscovery();

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) async {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.toLowerCase(),
      discoveredAt: discoveredAt ?? DateTime.utc(2026, 9, 17),
    );
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async => const [];
}

class _FakeBatchRunner implements ImportBatchRunner {
  const _FakeBatchRunner();

  @override
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    return ImportExecutionSummary(
      batchId: batch.id,
      totalCount: batch.totalCount,
      importedCount: batch.totalCount,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
    );
  }
}

class _FakeArtistCreationService extends ArtistCreationService {
  _FakeArtistCreationService() : super(mutationRunner: _UnusedMutationRunner());
}

class _UnusedMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Unused fake mutation runner.');
  }
}
