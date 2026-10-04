import '../../../../core/identity/artist_credit_parser.dart';
import '../../domain/repositories/artist_repository.dart';
import 'malformed_artist_identity_repair_service.dart';

typedef ArtistIdentityRepairOperation =
    Future<ArtistIdentityRepairResult> Function({
      required String? userId,
      required String artistId,
      DateTime? now,
    });

class ArtistIdentityRepairScanSummary {
  const ArtistIdentityRepairScanSummary({
    required this.scannedArtistCount,
    required this.candidateCount,
    required this.repairedCount,
    required this.sourceMissingCount,
    required this.notMalformedCount,
    required this.primaryArtistMissingCount,
    required this.primaryArtistAmbiguousCount,
    required this.targetArtistMalformedCount,
    required this.albumCollisionCount,
  });

  final int scannedArtistCount;
  final int candidateCount;
  final int repairedCount;
  final int sourceMissingCount;
  final int notMalformedCount;
  final int primaryArtistMissingCount;
  final int primaryArtistAmbiguousCount;
  final int targetArtistMalformedCount;
  final int albumCollisionCount;
}

class MalformedArtistIdentityRepairScanService {
  const MalformedArtistIdentityRepairScanService({
    required this.artistRepository,
    required this.repairArtist,
    this.artistCreditParser = const ArtistCreditParser(),
  });

  final ArtistRepository artistRepository;
  final ArtistIdentityRepairOperation repairArtist;
  final ArtistCreditParser artistCreditParser;

  Future<ArtistIdentityRepairScanSummary> repairAll({
    required String? userId,
    DateTime? now,
  }) async {
    final artists = await artistRepository.getAll();

    final candidateIds = [
      for (final artist in artists)
        if (artistCreditParser.parseExplicitFeatureCredit(artist.name) != null)
          artist.id,
    ];

    var repairedCount = 0;
    var sourceMissingCount = 0;
    var notMalformedCount = 0;
    var primaryArtistMissingCount = 0;
    var primaryArtistAmbiguousCount = 0;
    var targetArtistMalformedCount = 0;
    var albumCollisionCount = 0;

    for (final artistId in candidateIds) {
      final result = await repairArtist(
        userId: userId,
        artistId: artistId,
        now: now,
      );

      switch (result.status) {
        case ArtistIdentityRepairStatus.repaired:
          repairedCount++;
        case ArtistIdentityRepairStatus.sourceMissing:
          sourceMissingCount++;
        case ArtistIdentityRepairStatus.notMalformed:
          notMalformedCount++;
        case ArtistIdentityRepairStatus.primaryArtistMissing:
          primaryArtistMissingCount++;
        case ArtistIdentityRepairStatus.primaryArtistAmbiguous:
          primaryArtistAmbiguousCount++;
        case ArtistIdentityRepairStatus.targetArtistMalformed:
          targetArtistMalformedCount++;
        case ArtistIdentityRepairStatus.albumCollision:
          albumCollisionCount++;
      }
    }

    return ArtistIdentityRepairScanSummary(
      scannedArtistCount: artists.length,
      candidateCount: candidateIds.length,
      repairedCount: repairedCount,
      sourceMissingCount: sourceMissingCount,
      notMalformedCount: notMalformedCount,
      primaryArtistMissingCount: primaryArtistMissingCount,
      primaryArtistAmbiguousCount: primaryArtistAmbiguousCount,
      targetArtistMalformedCount: targetArtistMalformedCount,
      albumCollisionCount: albumCollisionCount,
    );
  }
}
