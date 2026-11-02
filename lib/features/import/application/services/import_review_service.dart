import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/artist_creation_service.dart';
import '../../../library/application/services/song_artist_credit_service.dart';
import '../../../library/application/services/track_profile_editing_service.dart';
import '../../../library/domain/entities/song_artist_credit.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/repositories/song_artist_credit_repository.dart';
import '../../domain/repositories/song_import_review_repository.dart';
import '../models/import_review_queue_item.dart';
import 'possible_recording_review_service.dart';

typedef ImportReviewClock = DateTime Function();

class ImportReviewService {
  ImportReviewService({
    required SongImportReviewRepository reviewRepository,
    required LibraryQueryRepository libraryQueryRepository,
    required TrackProfileEditingService trackProfileEditingService,
    required ArtistCreationService artistCreationService,
    required SongArtistCreditRepository songArtistCreditRepository,
    PossibleRecordingReviewService? possibleRecordings,
    ImportReviewClock? now,
  }) : this._(
         reviewRepository,
         libraryQueryRepository,
         trackProfileEditingService,
         artistCreationService,
         songArtistCreditRepository,
         possibleRecordings,
         now ?? DateTime.now,
       );

  const ImportReviewService._(
    this._reviewRepository,
    this._libraryQueryRepository,
    this._trackProfileEditingService,
    this._artistCreationService,
    this._songArtistCreditRepository,
    this.possibleRecordings,
    this._now,
  );

  final SongImportReviewRepository _reviewRepository;
  final LibraryQueryRepository _libraryQueryRepository;
  final TrackProfileEditingService _trackProfileEditingService;
  final ArtistCreationService _artistCreationService;
  final SongArtistCreditRepository _songArtistCreditRepository;
  final ImportReviewClock _now;

  /// Files kept out of the library as possible different recordings,
  /// reviewed in the same place as imported songs.
  final PossibleRecordingReviewService? possibleRecordings;

  /// Songs that need review, plus pending possible different recordings.
  Future<int> countUnresolved() async {
    final songs = await _reviewRepository.countUnresolved();
    var files = 0;

    try {
      files = (await possibleRecordings?.pending())?.length ?? 0;
    } catch (_) {
      // The device-local list never hides the songs that need review.
    }

    return songs + files;
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

  /// The song's stored artist credits, so the review editor starts from
  /// them and saving keeps every role (SN-50 C-Q5).
  Future<List<SongArtistCredit>> getCredits(String songId) {
    return _songArtistCreditRepository.getBySongId(songId);
  }

  Future<TrackProfileEditResult> updateTrackAndResolve({
    required String? userId,
    required ImportReviewQueueItem item,
    required String title,
    required int trackNumber,
    required int discNumber,
    required Iterable<SongArtistCreditInput> additionalCredits,
    required bool isSingle,
    required String artistId,
    required String albumId,
    String? moveToEditionId,
    String? placementEditionId,
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

    // Same save path and credit semantics as Track Studio: the edited
    // credits replace every credit other than the primary artist.
    final editResult = await reviewEditingService.updateTrackWithCredits(
      userId: normalizedUserId,
      songId: item.track.songId,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      additionalCredits: additionalCredits,
      isSingle: isSingle,
      artistId: artistId,
      albumId: albumId,
      // Only an album change moves the song between editions.
      albumEditionId: moveToEditionId,
      placementEditionId: placementEditionId,
      now: timestamp,
    );

    await _reviewRepository.save(
      currentReview.copyWith(resolvedAt: timestamp, updatedAt: timestamp),
    );

    return editResult;
  }
}
