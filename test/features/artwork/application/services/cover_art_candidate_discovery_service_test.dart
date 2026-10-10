import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/artwork/application/models/cover_art_archive_image.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_candidate_discovery_service.dart';
import 'package:sonus_next/features/artwork/data/services/cover_art_archive/cover_art_archive_client.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_candidate.dart';
import 'package:sonus_next/features/library/application/models/external_metadata_search_query.dart';
import 'package:sonus_next/features/library/data/services/musicbrainz/musicbrainz_http_transport.dart';

const releaseId = '11111111-1111-4111-8111-111111111111';
const releaseGroupId = '22222222-2222-4222-8222-222222222222';

void main() {
  group('CoverArtCandidateDiscoveryService', () {
    test('prefers release artwork when available', () async {
      final client = FakeCoverArtArchiveClient(
        responses: {
          'release:$releaseId': [
            image(CoverArtArchiveEntity.release, releaseId),
          ],
        },
      );

      final result = await CoverArtCandidateDiscoveryService(
        client: client,
      ).discover(candidate());

      expect(result, hasLength(1));
      expect(result.single.entity, CoverArtArchiveEntity.release);
      expect(client.requests, ['release:$releaseId']);
    });

    test('falls back to release group when release is empty', () async {
      final client = FakeCoverArtArchiveClient(
        responses: {
          'release-group:$releaseGroupId': [
            image(CoverArtArchiveEntity.releaseGroup, releaseGroupId),
          ],
        },
      );

      final result = await CoverArtCandidateDiscoveryService(
        client: client,
      ).discover(candidate());

      expect(result, hasLength(1));
      expect(result.single.entity, CoverArtArchiveEntity.releaseGroup);
      expect(client.requests, [
        'release:$releaseId',
        'release-group:$releaseGroupId',
      ]);
    });

    test('supports release-group-only candidates', () async {
      final client = FakeCoverArtArchiveClient();

      final result = await CoverArtCandidateDiscoveryService(
        client: client,
      ).discover(candidate(releaseIdValue: null));

      expect(result, isEmpty);
      expect(client.requests, ['release-group:$releaseGroupId']);
    });

    test('returns empty when both sources have no artwork', () async {
      final client = FakeCoverArtArchiveClient();

      final result = await CoverArtCandidateDiscoveryService(
        client: client,
      ).discover(candidate());

      expect(result, isEmpty);
      expect(client.requests, hasLength(2));
    });

    test('rejects invalid identifiers without network requests', () async {
      final client = FakeCoverArtArchiveClient();

      await expectLater(
        CoverArtCandidateDiscoveryService(client: client).discover(
          candidate(
            releaseIdValue: 'invalid-release',
            releaseGroupIdValue: 'invalid-group',
          ),
        ),
        throwsArgumentError,
      );

      expect(client.requests, isEmpty);
    });

    test('rejects non-album candidates', () async {
      final client = FakeCoverArtArchiveClient();

      await expectLater(
        CoverArtCandidateDiscoveryService(client: client).discover(
          const ExternalMetadataCandidate(
            provider: ExternalMetadataProviderKind.musicBrainz,
            entityKind: ExternalMetadataEntityKind.track,
            providerEntityId: releaseGroupId,
            displayName: 'Test Track',
          ),
        ),
        throwsArgumentError,
      );

      expect(client.requests, isEmpty);
    });

    test('uses typed external IDs when candidate IDs are absent', () async {
      final client = FakeCoverArtArchiveClient();

      await CoverArtCandidateDiscoveryService(client: client).discover(
        const ExternalMetadataCandidate(
          provider: ExternalMetadataProviderKind.musicBrainz,
          entityKind: ExternalMetadataEntityKind.album,
          providerEntityId: releaseGroupId,
          displayName: 'Test Album',
          externalIds: {
            'musicBrainzReleaseId': releaseId,
            'musicBrainzReleaseGroupId': releaseGroupId,
          },
        ),
      );

      expect(client.requests, [
        'release:$releaseId',
        'release-group:$releaseGroupId',
      ]);
    });
  });
}

ExternalMetadataCandidate candidate({
  String? releaseIdValue = releaseId,
  String releaseGroupIdValue = releaseGroupId,
}) {
  return ExternalMetadataCandidate(
    provider: ExternalMetadataProviderKind.musicBrainz,
    entityKind: ExternalMetadataEntityKind.album,
    providerEntityId: releaseGroupIdValue,
    displayName: 'Test Album',
    releaseId: releaseIdValue,
    releaseGroupId: releaseGroupIdValue,
  );
}

CoverArtArchiveImage image(CoverArtArchiveEntity entity, String id) {
  return CoverArtArchiveImage(
    entity: entity,
    entityId: id,
    imageUrl: 'https://coverartarchive.org/test.jpg',
    front: true,
    back: false,
  );
}

class FakeCoverArtArchiveClient extends CoverArtArchiveClient {
  FakeCoverArtArchiveClient({this.responses = const {}})
    : super(transport: _UnusedTransport(), userAgent: 'SonusTests/1.0');

  final Map<String, List<CoverArtArchiveImage>> responses;
  final List<String> requests = [];

  @override
  Future<List<CoverArtArchiveImage>> lookup({
    required CoverArtArchiveEntity entity,
    required String id,
  }) async {
    final key = '${entity.path}:$id';
    requests.add(key);
    return responses[key] ?? const [];
  }
}

class _UnusedTransport implements MusicBrainzHttpTransport {
  @override
  Future<MusicBrainzHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    throw StateError('No HTTP requests expected.');
  }
}
