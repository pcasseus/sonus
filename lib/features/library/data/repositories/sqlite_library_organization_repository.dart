import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_tables.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../domain/entities/library_organization.dart';
import '../../domain/repositories/library_organization_repository.dart';

/// Writes go through [AppDatabase.transaction], so they wait for, and are
/// refused during, a restore like every other library mutation.
class SqliteLibraryOrganizationRepository
    implements LibraryOrganizationRepository {
  SqliteLibraryOrganizationRepository(
    this.appDatabase, {
    LibraryChangeSignal? changes,
  }) : _changes = changes ?? LibraryChangeSignal.shared;

  final AppDatabase appDatabase;
  final LibraryChangeSignal _changes;

  Future<void> _write(
    Future<void> Function(Transaction transaction) action,
  ) async {
    await appDatabase.transaction(action);
    _changes.notify(LibraryChangeKind.libraryEdited);
  }

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.albumReleaseClassifications,
      where: 'kind IS NOT NULL',
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
    return _write(
      (transaction) => _upsert(
        transaction,
        albumId: classification.albumId,
        values: {
          'kind': classification.kind.name,
          'authority': classification.authority.name,
          'source_reference': classification.sourceReference,
        },
        createdAt: classification.createdAt,
        updatedAt: classification.updatedAt,
      ),
    );
  }

  @override
  Future<void> deleteClassification(String albumId) {
    return _write(
      (transaction) => _clear(
        transaction,
        albumId,
        const ['kind', 'authority', 'source_reference'],
        others: const ['format', 'live'],
      ),
    );
  }

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.albumReleaseClassifications,
      where: 'format IS NOT NULL',
      orderBy: 'album_id ASC',
    );

    return [
      for (final row in rows)
        AlbumReleaseFormat(
          albumId: row['album_id']! as String,
          format: ReleaseFormat.values.byName(row['format']! as String),
          authority: ReleaseClassificationAuthority.values.byName(
            row['format_authority']! as String,
          ),
          sourceReference: row['format_source_reference'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
    ];
  }

  @override
  Future<void> saveFormat(AlbumReleaseFormat format) {
    return _write(
      (transaction) => _upsert(
        transaction,
        albumId: format.albumId,
        values: {
          'format': format.format.name,
          'format_authority': format.authority.name,
          'format_source_reference': format.sourceReference,
        },
        createdAt: format.createdAt,
        updatedAt: format.updatedAt,
      ),
    );
  }

  @override
  Future<void> deleteFormat(String albumId) {
    return _write(
      (transaction) => _clear(
        transaction,
        albumId,
        const ['format', 'format_authority', 'format_source_reference'],
        others: const ['kind', 'live'],
      ),
    );
  }

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseTables.albumReleaseClassifications,
      where: 'live IS NOT NULL',
      orderBy: 'album_id ASC',
    );

    return [
      for (final row in rows)
        AlbumLiveClassification(
          albumId: row['album_id']! as String,
          isLive: row['live'] == 1,
          authority: ReleaseClassificationAuthority.values.byName(
            row['live_authority']! as String,
          ),
          sourceReference: row['live_source_reference'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String),
        ),
    ];
  }

  @override
  Future<void> saveLiveClassification(AlbumLiveClassification live) {
    return _write(
      (transaction) => _upsert(
        transaction,
        albumId: live.albumId,
        values: {
          'live': live.isLive ? 1 : 0,
          'live_authority': live.authority.name,
          'live_source_reference': live.sourceReference,
        },
        createdAt: live.createdAt,
        updatedAt: live.updatedAt,
      ),
    );
  }

  @override
  Future<void> deleteLiveClassification(String albumId) {
    return _write(
      (transaction) => _clear(
        transaction,
        albumId,
        const ['live', 'live_authority', 'live_source_reference'],
        others: const ['kind', 'format'],
      ),
    );
  }

  /// Sets one fact of the album's row, keeping the other.
  Future<void> _upsert(
    Transaction transaction, {
    required String albumId,
    required Map<String, Object?> values,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final updated = await transaction.update(
      DatabaseTables.albumReleaseClassifications,
      {...values, 'updated_at': updatedAt.toUtc().toIso8601String()},
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
    if (updated > 0) return;

    await transaction.insert(DatabaseTables.albumReleaseClassifications, {
      'album_id': albumId,
      ...values,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    });
  }

  /// Clears one fact; the row goes once none of [others] is set either.
  Future<void> _clear(
    Transaction transaction,
    String albumId,
    List<String> columns, {
    required List<String> others,
  }) async {
    await transaction.delete(
      DatabaseTables.albumReleaseClassifications,
      where: [
        'album_id = ?',
        for (final other in others) '$other IS NULL',
      ].join(' AND '),
      whereArgs: [albumId],
    );
    await transaction.update(
      DatabaseTables.albumReleaseClassifications,
      {for (final column in columns) column: null},
      where: 'album_id = ?',
      whereArgs: [albumId],
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
    return _write(
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
    return _write(
      (transaction) => transaction.delete(
        DatabaseTables.artistProjectAssignments,
        where: 'artist_id = ?',
        whereArgs: [artistId],
      ),
    );
  }
}
