import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/artist_creation_service.dart';
import '../../../library/application/services/track_profile_editing_service.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../models/import_review_queue_item.dart';

typedef ImportReviewClock = DateTime Function();

class ImportReviewService {
  ImportReviewService({
    required SongImportReviewRepository reviewRepository,
    required LibraryQueryRepository libraryQueryRepository,
    required TrackProfileEditingService trackProfileEditingService,
    required ArtistCreationService artistCreationService,
    ImportReviewClock? now,
  }) : this._(
         reviewRepository,
         libraryQueryRepository,
         trackProfileEditingService,
         artistCreationService,
         now ?? DateTime.now,
       );

  const ImportReviewService._(
    this._reviewRepository,
    this._libraryQueryRepository,
    this._trackProfileEditingService,
    this._artistCreationService,
    this._now,
  );

  final SongImportReviewRepository _reviewRepository;
  final LibraryQueryRepository _libraryQueryRepository;
  final TrackProfileEditingService _trackProfileEditingService;
  final ArtistCreationService _artistCreationService;
  final ImportReviewClock _now;

  Future<int> countUnresolved() {
    return _reviewRepository.countUnresolved();
  }

  Future<List<ImportReviewQueueItem>> getUnresolved() async {
    final reviews = await _reviewRepository.getUnresolved();
    final items = <ImportReviewQueueItem>[];

    for (final review in reviews) {
      final track = await _libraryQueryRepository.getTrackById(review.songId);

      if (track == null) {
        throw StateError('Track not found for import review: ${review.songId}');
      }

      items.add(ImportReviewQueueItem(review: review, track: track));
    }

    return List<ImportReviewQueueItem>.unmodifiable(items);
  }

  Future<List<LibraryArtist>> getArtists() {
    return _libraryQueryRepository.getArtists();
  }

  Future<LibraryArtist> createOrReuseArtist({
    required String? userId,
    required String name,
  }) async {
    final artist = await _artistCreationService.createOrReuse(
      userId: userId,
      name: name,
    );

    final artists = await _libraryQueryRepository.getArtists();

    for (final libraryArtist in artists) {
      if (libraryArtist.artistId == artist.id) {
        return libraryArtist;
      }
    }

    throw StateError('Created artist not found in library query: ${artist.id}');
  }

  Future<List<LibraryAlbum>> getAlbums() {
    return _libraryQueryRepository.getAlbums();
  }

  Future<TrackProfileEditResult> updateTrackAndResolve({
    required String? userId,
    required ImportReviewQueueItem item,
    required String title,
    required int trackNumber,
    required int discNumber,
    required List<String> featuredArtists,
    required bool isSingle,
    required String artistId,
    required String albumId,
    required String albumEditionId,
    DateTime? now,
  }) async {
    final normalizedUserId = userId?.trim();

    final currentReview = await _reviewRepository.getBySongId(
      item.review.songId,
    );

    if (currentReview == null) {
      throw StateError('Import review not found: ${item.review.songId}');
    }

    if (currentReview.isResolved) {
      throw StateError(
        'Import review is already resolved: ${item.review.songId}',
      );
    }

    final timestamp = now ?? _now();

    final reviewEditingService = _trackProfileEditingService
        .withMetadataProvenance(
          authority: MetadataAuthority.confirmed,
          source: MetadataProvenanceSource.review,
        );

    final editResult = await reviewEditingService.updateTrack(
      userId: normalizedUserId,
      songId: item.track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      featuredArtists: featuredArtists,
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: albumEditionId,
      now: timestamp,
    );

    await _reviewRepository.save(
      currentReview.copyWith(resolvedAt: timestamp, updatedAt: timestamp),
    );

    return editResult;
  }
}
