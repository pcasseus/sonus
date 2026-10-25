import '../entities/library_organization.dart';

/// Release classifications and artist placements. Device-local: not synced
/// and not in backups.
abstract interface class LibraryOrganizationRepository {
  Future<List<AlbumReleaseClassification>> getClassifications();

  Future<void> saveClassification(AlbumReleaseClassification classification);

  Future<void> deleteClassification(String albumId);

  Future<List<ArtistProjectAssignment>> getAssignments();

  Future<void> saveAssignment(ArtistProjectAssignment assignment);

  Future<void> deleteAssignment(String artistId);
}
