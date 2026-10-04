abstract interface class ArtistIdentityRepairRepository {
  Future<void> remapHistoricalArtistReferences({
    required String sourceArtistId,
    required String targetArtistId,
    required String targetArtistName,
  });
}
