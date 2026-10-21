import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/models/artist_dependency_journal_entry.dart';

class ArtistDependencyJournalDao {
  const ArtistDependencyJournalDao(this.db);

  final DatabaseExecutor db;

  static const table = SyncSchema.artistDependencyJournalTable;

  Future<ArtistDependencyJournalEntry?> findUnresolved({
    required String userId,
    required String artistId,
  }) async {
    final rows = await db.query(
      table,
      where: 'user_id = ? AND artist_id = ?',
      whereArgs: [userId, artistId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return ArtistDependencyJournalEntry.fromRow(rows.single);
  }

  Future<List<ArtistDependencyJournalEntry>> findUnresolvedForUser(
    String userId,
  ) async {
    final rows = await db.query(
      table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC, artist_id ASC',
    );

    return rows
        .map(ArtistDependencyJournalEntry.fromRow)
        .toList(growable: false);
  }

  /// Reuses only an identical durable snapshot.
  ///
  /// Different requests for the same artist cannot replace
  /// an unresolved dependency operation.
  Future<void> prepare(ArtistDependencyJournalEntry entry) async {
    final existing = await findUnresolved(
      userId: entry.userId,
      artistId: entry.artistId,
    );

    if (existing != null) {
      if (existing.sameSnapshot(entry)) return;

      throw StateError('Artist has a different unresolved dependency.');
    }

    try {
      await db.insert(table, entry.toRow());
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError()) rethrow;

      final raced = await findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (raced != null && raced.sameSnapshot(entry)) return;

      throw StateError('Conflicting artist dependency request.');
    }
  }

  /// Call only after a verified server receipt, in the same
  /// SQLite transaction that saves the observed server revision.
  Future<int> removeVerified(ArtistDependencyJournalEntry entry) {
    return db.delete(
      table,
      where:
          'user_id = ? AND artist_id = ? '
          'AND request_id = ? AND mutation_revision = ? '
          'AND request_json = ? AND created_at = ?',
      whereArgs: [
        entry.userId,
        entry.artistId,
        entry.requestId,
        entry.mutationRevision,
        entry.requestJson,
        entry.createdAt.toUtc().toIso8601String(),
      ],
    );
  }
}
