import '../entities/library_organization.dart';

/// Release classifications, release formats and artist placements. Kept in
/// backups and the cloud archive.
abstract interface class LibraryOrganizationRepository {
  Future<List<AlbumReleaseClassification>> getClassifications();

  Future<void> saveClassification(AlbumReleaseClassification classification);

  Future<void> deleteClassification(String albumId);

  Future<List<AlbumReleaseFormat>> getFormats();

  Future<void> saveFormat(AlbumReleaseFormat format);

  Future<void> deleteFormat(String albumId);

  Future<List<AlbumLiveClassification>> getLiveClassifications();

  Future<void> saveLiveClassification(AlbumLiveClassification live);

  Future<void> deleteLiveClassification(String albumId);

  Future<List<ArtistProjectAssignment>> getAssignments();

  Future<void> saveAssignment(ArtistProjectAssignment assignment);

  Future<void> deleteAssignment(String artistId);
}
