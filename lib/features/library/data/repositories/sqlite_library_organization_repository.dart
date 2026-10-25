import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../domain/entities/library_organization.dart';
import '../../domain/repositories/library_organization_repository.dart';

/// Writes go through [AppDatabase.transaction], so they wait for, and are
/// refused during, a restore like every other library mutation.
class SqliteLibraryOrganizationRepository
    implements LibraryOrganizationRepository {
  const SqliteLibraryOrganizationRepository(this.appDatabase);

  final AppDatabase appDatabase;

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.albumReleaseClassifications,
      orderBy: 'album_id ASC',
    );

    return [
      for (final row in rows)
        AlbumReleaseClassification(
          albumId: row['album_id']! as String,
          kind: ReleaseKind.values.byName(row['kind']! as String),
          authority: ReleaseClassificationAuthority.values.byName(
            row['authority']! as String,
          ),
          sourceReference: row['source_reference'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
    ];
  }

  @override
  Future<void> saveClassification(AlbumReleaseClassification classification) {
    return appDatabase.transaction(
      (transaction) =>
          transaction.insert(DatabaseTables.albumReleaseClassifications, {
            'album_id': classification.albumId,
            'kind': classification.kind.name,
            'authority': classification.authority.name,
            'source_reference': classification.sourceReference,
            'created_at': classification.createdAt.toUtc().toIso8601String(),
            'updated_at': classification.updatedAt.toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  @override
  Future<void> deleteClassification(String albumId) {
    return appDatabase.transaction(
      (transaction) => transaction.delete(
        DatabaseTables.albumReleaseClassifications,
        where: 'album_id = ?',
        whereArgs: [albumId],
      ),
    );
  }

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.artistProjectAssignments,
      orderBy: 'artist_id ASC',
    );

    return [
      for (final row in rows)
        ArtistProjectAssignment(
          artistId: row['artist_id']! as String,
          albumId: row['album_id'] as String?,
          mode: ArtistProjectAssignmentMode.values.byName(
            row['mode']! as String,
          ),
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
    ];
  }

  @override
  Future<void> saveAssignment(ArtistProjectAssignment assignment) {
    return appDatabase.transaction(
      (transaction) =>
          transaction.insert(DatabaseTables.artistProjectAssignments, {
            'artist_id': assignment.artistId,
            'album_id': assignment.albumId,
            'mode': assignment.mode.name,
            'created_at': assignment.createdAt.toUtc().toIso8601String(),
            'updated_at': assignment.updatedAt.toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  @override
  Future<void> deleteAssignment(String artistId) {
    return appDatabase.transaction(
      (transaction) => transaction.delete(
        DatabaseTables.artistProjectAssignments,
        where: 'artist_id = ?',
        whereArgs: [artistId],
      ),
    );
  }
}
