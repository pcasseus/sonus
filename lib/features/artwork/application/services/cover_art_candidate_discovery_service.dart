import '../../../library/application/models/external_metadata_candidate.dart';
import '../../../library/application/models/external_metadata_search_query.dart';
import '../../data/services/cover_art_archive/cover_art_archive_client.dart';
import '../models/cover_art_archive_image.dart';

class CoverArtCandidateDiscoveryService {
  const CoverArtCandidateDiscoveryService({required this.client});

  final CoverArtArchiveClient client;

  static final RegExp _mbidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<List<CoverArtArchiveImage>> discover(
    ExternalMetadataCandidate candidate,
  ) async {
    if (candidate.provider != ExternalMetadataProviderKind.musicBrainz ||
        candidate.entityKind != ExternalMetadataEntityKind.album) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'A MusicBrainz album candidate is required.',
      );
    }

    final releaseId = _validatedId(
      candidate.releaseId ?? candidate.externalIds['musicBrainzReleaseId'],
    );

    final releaseGroupId = _validatedId(
      candidate.releaseGroupId ??
          candidate.externalIds['musicBrainzReleaseGroupId'] ??
          candidate.providerEntityId,
    );

    if (releaseId == null && releaseGroupId == null) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'A valid MusicBrainz release or release-group ID is required.',
      );
    }

    if (releaseId != null) {
      final releaseImages = await client.lookup(
        entity: CoverArtArchiveEntity.release,
        id: releaseId,
      );

      if (releaseImages.isNotEmpty) {
        return releaseImages;
      }
    }

    if (releaseGroupId != null) {
      return client.lookup(
        entity: CoverArtArchiveEntity.releaseGroup,
        id: releaseGroupId,
      );
    }

    return const [];
  }

  static String? _validatedId(String? value) {
    final normalized = value?.trim().toLowerCase();

    if (normalized == null || !_mbidPattern.hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }
}
