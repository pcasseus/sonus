import 'cover_art_archive_downloader.dart';
import 'cover_art_cancellation.dart';
import 'cover_art_image_validator.dart';

class CoverArtValidatedDownloadService {
  const CoverArtValidatedDownloadService({
    required this.downloader,
    required this.validator,
  });

  final CoverArtArchiveDownloader downloader;
  final CoverArtImageValidator validator;

  Future<CoverArtDownloadResult> download(
    Uri imageUri, {
    CoverArtCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final result = await downloader.download(
      imageUri,
      cancellationToken: cancellationToken,
    );

    try {
      cancellationToken?.throwIfCancelled();
      await validator.validate(result.filePath);
      cancellationToken?.throwIfCancelled();
      return result;
    } catch (_) {
      try {
        await result.deleteTemporaryFiles();
      } catch (_) {
        // Preserve the original validation failure.
      }

      rethrow;
    }
  }
}
