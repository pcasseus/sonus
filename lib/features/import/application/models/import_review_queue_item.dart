import '../../../library/application/models/library_track.dart';
import '../../domain/entities/song_import_review.dart';

class ImportReviewQueueItem {
  const ImportReviewQueueItem({required this.review, required this.track});

  final SongImportReview review;
  final LibraryTrack track;
}
