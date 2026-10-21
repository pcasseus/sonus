import 'package:sqflite/sqflite.dart';

import '../../../../core/database/schema/sync_schema.dart';
import '../../domain/models/artist_write_journal_entry.dart';

class ArtistWriteJournalDao {
  const ArtistWriteJournalDao(this.db);

  final DatabaseExecutor db;

  static const table = SyncSchema.artistWriteJournalTable;

  Future<ArtistWriteJournalEntry?> findUnresolved({
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

    return ArtistWriteJournalEntry.fromRow(rows.single);
  }

  Future<List<ArtistWriteJournalEntry>> findUnresolvedForUser(
    String userId,
  ) async {
    final rows = await db.query(
      table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC, artist_id ASC',
    );

    return rows.map(ArtistWriteJournalEntry.fromRow).toList(growable: false);
  }

  /// Idempotent only for an identical immutable request snapshot.
  ///
  /// A different request for the same artist must never replace an
  /// unresolved cloud operation.
  Future<void> prepare(ArtistWriteJournalEntry entry) async {
    final existing = await findUnresolved(
      userId: entry.userId,
      artistId: entry.artistId,
    );

    if (existing != null) {
      if (existing.sameSnapshot(entry)) return;

      throw StateError('Artist has a different unresolved cloud request.');
    }

    try {
      await db.insert(table, entry.toRow());
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError()) rethrow;

      // A concurrent writer may have inserted after our first read.
      final raced = await findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (raced != null && raced.sameSnapshot(entry)) return;

      throw StateError('Conflicting artist journal receipt or request.');
    }
  }

  /// Call only after a verified outcome, inside the same SQLite
  /// transaction that persists the resulting server revision.
  Future<int> removeVerified(ArtistWriteJournalEntry entry) {
    final revision = entry.expectedServerRevision;
    final revisionPredicate = revision == null
        ? 'expected_server_revision IS NULL'
        : 'expected_server_revision = ?';
    return db.delete(
      table,
      where:
          'user_id = ? AND artist_id = ? AND outbox_id = ? '
          'AND mutation_revision = ? AND operation = ? '
          'AND $revisionPredicate AND request_json = ? '
          'AND created_at = ?',
      whereArgs: [
        entry.userId,
        entry.artistId,
        entry.outboxId,
        entry.mutationRevision,
        entry.operation.name,
        ?revision,
        entry.requestJson,
        entry.createdAt.toUtc().toIso8601String(),
      ],
    );
  }
}
