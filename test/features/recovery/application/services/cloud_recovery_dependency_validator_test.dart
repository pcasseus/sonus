import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/recovery/application/models/cloud_recovery_dependency_issue.dart';
import 'package:sonus_next/features/recovery/application/services/cloud_recovery_dependency_validator.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

final now = DateTime.utc(2026, 10, 21);

CloudArtistRecord artist(String id, {bool deleted = false}) =>
    CloudArtistRecord(
      id: id,
      userId: 'user-a',
      name: id,
      canonicalName: id,
      createdAt: now,
      updatedAt: now,
      deletedAt: deleted ? now : null,
    );

CloudAlbumRecord album(String id, String artistId) => CloudAlbumRecord(
  id: id,
  userId: 'user-a',
  artistId: artistId,
  title: id,
  canonicalTitle: id,
  createdAt: now,
  updatedAt: now,
);

CloudAlbumEditionRecord edition(String id, String albumId) =>
    CloudAlbumEditionRecord(
      id: id,
      userId: 'user-a',
      albumId: albumId,
      title: id,
      type: 'standard',
      isPrimary: true,
      createdAt: now,
      updatedAt: now,
    );

CloudSongRecord song(String id, String albumId, String editionId) =>
    CloudSongRecord(
      id: id,
      userId: 'user-a',
      artistId: 'artist-1',
      albumId: albumId,
      albumEditionId: editionId,
      title: id,
      canonicalTitle: id,
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: const [],
      createdAt: now,
      updatedAt: now,
    );

void main() {
  const validator = CloudRecoveryDependencyValidator();

  test('accepts a structurally complete library', () {
    final issues = validator.validate([
      artist('artist-1'),
      album('album-1', 'artist-1'),
      edition('edition-1', 'album-1'),
      song('song-1', 'album-1', 'edition-1'),
    ]);

    expect(issues, isEmpty);
  });

  test('reports missing parent artists', () {
    final issues = validator.validate([album('album-1', 'missing-artist')]);

    expect(
      issues.single.kind,
      CloudRecoveryDependencyIssueKind.missingReference,
    );
    expect(issues.single.referencedId, 'missing-artist');
  });

  test('reports references to deleted parents', () {
    final issues = validator.validate([
      artist('artist-1', deleted: true),
      album('album-1', 'artist-1'),
    ]);

    expect(
      issues.single.kind,
      CloudRecoveryDependencyIssueKind.deletedReference,
    );
  });

  test('detects edition and song album mismatch', () {
    final issues = validator.validate([
      artist('artist-1'),
      album('album-1', 'artist-1'),
      album('album-2', 'artist-1'),
      edition('edition-1', 'album-1'),
      song('song-1', 'album-2', 'edition-1'),
    ]);

    expect(
      issues.any(
        (issue) =>
            issue.kind == CloudRecoveryDependencyIssueKind.editionAlbumMismatch,
      ),
      isTrue,
    );
  });

  test('rejects duplicate cloud identities', () {
    expect(
      () => validator.validate([artist('artist-1'), artist('artist-1')]),
      throwsStateError,
    );
  });

  test('returns immutable findings', () {
    final issues = validator.validate([album('album-1', 'missing-artist')]);

    expect(() => issues.clear(), throwsUnsupportedError);
  });
}
