import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/services/malformed_artist_identity_repair_scan_service.dart';
import 'package:sonus_next/features/library/application/services/malformed_artist_identity_repair_service.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/repositories/artist_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);

  Artist artist(String name) {
    return EntityFactory.createArtist(name: name, now: now);
  }

  test('prefilters clean artists and summarizes repair outcomes', () async {
    final repaired = artist('Alpha feat. Guest');
    final missingPrimary = artist('Beta [Ft. Guest]');
    final ambiguousPrimary = artist('Gamma featuring Guest');
    final malformedTarget = artist('Delta ft Guest');
    final collision = artist('Epsilon (feat. Guest)');
    final sourceMissing = artist('Zeta ft. Guest');
    final becameClean = artist('Eta feat. Guest');

    final repository = _FakeArtistRepository([
      artist('Clean Artist'),
      artist('Simon & Garfunkel'),
      repaired,
      missingPrimary,
      ambiguousPrimary,
      malformedTarget,
      collision,
      sourceMissing,
      becameClean,
    ]);

    final calls = <String>[];
    final receivedUsers = <String?>[];
    final receivedTimes = <DateTime?>[];

    final statuses = <String, ArtistIdentityRepairStatus>{
      repaired.id: ArtistIdentityRepairStatus.repaired,
      missingPrimary.id: ArtistIdentityRepairStatus.primaryArtistMissing,
      ambiguousPrimary.id: ArtistIdentityRepairStatus.primaryArtistAmbiguous,
      malformedTarget.id: ArtistIdentityRepairStatus.targetArtistMalformed,
      collision.id: ArtistIdentityRepairStatus.albumCollision,
      sourceMissing.id: ArtistIdentityRepairStatus.sourceMissing,
      becameClean.id: ArtistIdentityRepairStatus.notMalformed,
    };

    Future<ArtistIdentityRepairResult> repair({
      required String? userId,
      required String artistId,
      DateTime? now,
    }) async {
      calls.add(artistId);
      receivedUsers.add(userId);
      receivedTimes.add(now);

      return ArtistIdentityRepairResult(
        status: statuses[artistId]!,
        sourceArtistId: artistId,
      );
    }

    final service = MalformedArtistIdentityRepairScanService(
      artistRepository: repository,
      repairArtist: repair,
    );

    final summary = await service.repairAll(userId: 'user_1', now: now);

    expect(summary.scannedArtistCount, 9);
    expect(summary.candidateCount, 7);
    expect(summary.repairedCount, 1);
    expect(summary.sourceMissingCount, 1);
    expect(summary.notMalformedCount, 1);
    expect(summary.primaryArtistMissingCount, 1);
    expect(summary.primaryArtistAmbiguousCount, 1);
    expect(summary.targetArtistMalformedCount, 1);
    expect(summary.albumCollisionCount, 1);

    expect(calls, hasLength(7));
    expect(calls, isNot(contains(repository.artists[0].id)));
    expect(calls, isNot(contains(repository.artists[1].id)));
    expect(receivedUsers, everyElement('user_1'));
    expect(receivedTimes, everyElement(now));
  });

  test('uses a snapshot of candidate ids before repair begins', () async {
    final first = artist('Alpha feat. Guest');
    final second = artist('Beta feat. Guest');

    final repository = _FakeArtistRepository([first, second]);

    final calls = <String>[];

    Future<ArtistIdentityRepairResult> repair({
      required String? userId,
      required String artistId,
      DateTime? now,
    }) async {
      calls.add(artistId);

      if (calls.length == 1) {
        repository.artists.add(artist('Added Later feat. Guest'));
      }

      return ArtistIdentityRepairResult(
        status: ArtistIdentityRepairStatus.primaryArtistMissing,
        sourceArtistId: artistId,
      );
    }

    final service = MalformedArtistIdentityRepairScanService(
      artistRepository: repository,
      repairArtist: repair,
    );

    final summary = await service.repairAll(userId: null, now: now);

    expect(summary.scannedArtistCount, 2);
    expect(summary.candidateCount, 2);
    expect(summary.primaryArtistMissingCount, 2);
    expect(calls, [first.id, second.id]);
    expect(repository.artists, hasLength(3));
  });
}

class _FakeArtistRepository implements ArtistRepository {
  _FakeArtistRepository(this.artists);

  final List<Artist> artists;

  @override
  Future<List<Artist>> getAll() async {
    return List<Artist>.unmodifiable(artists);
  }

  @override
  Future<Artist?> getById(String id) {
    throw UnsupportedError('getById is not used by this test.');
  }

  @override
  Future<void> create(Artist artist) {
    throw UnsupportedError('create is not used by this test.');
  }

  @override
  Future<void> save(Artist artist) {
    throw UnsupportedError('save is not used by this test.');
  }

  @override
  Future<void> delete(String id) {
    throw UnsupportedError('delete is not used by this test.');
  }
}
