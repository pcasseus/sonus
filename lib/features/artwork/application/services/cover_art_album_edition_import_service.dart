import '../../application/models/cover_art_archive_image.dart';
import '../../data/services/cover_art_archive/cover_art_archive_downloader.dart';
import '../../data/services/cover_art_archive/cover_art_cancellation.dart';
import '../../data/services/cover_art_archive/cover_art_validated_download_service.dart';
import 'cover_art_album_edition_assignment_service.dart';
import 'owned_artwork_managed_storage.dart';

class CoverArtAlbumEditionImportService {
  const CoverArtAlbumEditionImportService({
    required this.downloadService,
    required this.managedStorage,
    required this.assignmentService,
  });

  final CoverArtValidatedDownloadService downloadService;
  final OwnedArtworkManagedStorage managedStorage;
  final CoverArtAlbumEditionAssignmentService assignmentService;

  Future<CoverArtAlbumEditionAssignmentResult> importImage({
    required String albumEditionId,
    required CoverArtArchiveImage image,
    String? userId,
    CoverArtCancellationToken? cancellationToken,
    DateTime? now,
  }) async {
    cancellationToken?.throwIfCancelled();

    final imageUri = Uri.tryParse(image.imageUrl.trim());

    if (imageUri == null || !imageUri.hasScheme) {
      throw ArgumentError.value(
        image.imageUrl,
        'image.imageUrl',
        'A valid image URL is required.',
      );
    }

    CoverArtDownloadResult? download;
    OwnedArtworkImport? ownedImport;
    var retained = false;

    try {
      // Read authority before performing any network or file operation.
      // The assignment service repeats this check transactionally later.
      final precheck = await assignmentService.evaluateBeforeDownload(
        albumEditionId: albumEditionId,
      );

      cancellationToken?.throwIfCancelled();

      if (!precheck.applied) {
        return precheck;
      }

      download = await downloadService.download(
        imageUri,
        cancellationToken: cancellationToken,
      );

      cancellationToken?.throwIfCancelled();

      ownedImport = await managedStorage.importOwnedArtwork(download.filePath);

      cancellationToken?.throwIfCancelled();

      final result = await assignmentService.assignManagedArtwork(
        albumEditionId: albumEditionId,
        managedFilePath: ownedImport.filePath,
        sourceReference: image.sourceReference,
        userId: userId,
        now: now,
      );

      retained = result.applied;

      if (!retained) {
        await ownedImport.discard();
        ownedImport = null;
      }

      await download.deleteTemporaryFiles();
      download = null;

      return result;
    } catch (error, stackTrace) {
      if (!retained && ownedImport != null) {
        try {
          await ownedImport.discard();
        } catch (_) {
          // Preserve the original workflow failure.
        }
      }

      if (download != null) {
        try {
          await download.deleteTemporaryFiles();
        } catch (_) {
          // Preserve the original workflow failure.
        }
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
