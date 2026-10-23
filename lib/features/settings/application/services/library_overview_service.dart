import 'package:flutter/foundation.dart';

import '../../../import/application/services/import_review_service.dart';
import '../../../import/application/services/import_workflow_service.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';

/// A read-only summary of the library for Settings.
@immutable
class LibraryOverview {
  const LibraryOverview({
    required this.songCount,
    required this.albumCount,
    required this.artistCount,
    required this.unavailableSongs,
    required this.blacklistedSongCount,
    required this.importSourceCount,
    required this.pendingReviewCount,
  });

  final int songCount;
  final int albumCount;
  final int artistCount;

  /// Songs whose audio file is not available on this device, by title.
  final List<LibraryTrack> unavailableSongs;
  final int blacklistedSongCount;

  /// Null when the import system is not ready.
  final int? importSourceCount;

  /// Null when the review queue is not ready.
  final int? pendingReviewCount;
}

/// Builds a [LibraryOverview] from the existing library, import and review
/// services. It only reads; nothing is scanned, relinked or changed.
class LibraryOverviewService {
  const LibraryOverviewService({
    required this.library,
    this.imports,
    this.reviews,
  });

  final LibraryQueryRepository library;
  final ImportWorkflowService? imports;
  final ImportReviewService? reviews;

  Future<LibraryOverview> load() async {
    final tracks = await library.getTracks();
    final albums = await library.getAlbums();
    final artists = await library.getArtists();
    final sources = await imports?.getSources();
    final pendingReviews = await reviews?.countUnresolved();

    return LibraryOverview(
      songCount: tracks.length,
      albumCount: albums.length,
      artistCount: artists.length,
      unavailableSongs: List.unmodifiable(
        tracks.where((track) => !track.isAvailable),
      ),
      blacklistedSongCount: tracks.where((track) => track.isBlocked).length,
      importSourceCount: sources?.length,
      pendingReviewCount: pendingReviews,
    );
  }
}
