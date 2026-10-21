import 'dart:convert';

enum ArtistWriteJournalOperation { create, update, delete }

class ArtistWriteJournalEntry {
  ArtistWriteJournalEntry({
    required this.userId,
    required this.artistId,
    required this.outboxId,
    required this.mutationRevision,
    required this.operation,
    required this.expectedServerRevision,
    required this.requestJson,
    required this.createdAt,
  }) {
    if (userId.trim().isEmpty ||
        artistId.trim().isEmpty ||
        outboxId.trim().isEmpty ||
        mutationRevision < 1) {
      throw ArgumentError('Invalid artist journal identity.');
    }

    if (operation == ArtistWriteJournalOperation.create) {
      if (expectedServerRevision != null) {
        throw ArgumentError('Creation cannot have an expected revision.');
      }
    } else if (expectedServerRevision == null || expectedServerRevision! < 1) {
      throw ArgumentError('Update/delete requires a positive revision.');
    }

    final decoded = jsonDecode(requestJson);

    if (decoded is! Map<String, dynamic> || decoded.isEmpty) {
      throw ArgumentError('Journal request must be a nonempty JSON object.');
    }

    if (createdAt.isUtc == false) {
      throw ArgumentError('Journal creation timestamp must be UTC.');
    }
  }

  final String userId;
  final String artistId;
  final String outboxId;
  final int mutationRevision;
  final ArtistWriteJournalOperation operation;
  final int? expectedServerRevision;
  final String requestJson;
  final DateTime createdAt;

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'artist_id': artistId,
    'outbox_id': outboxId,
    'mutation_revision': mutationRevision,
    'operation': operation.name,
    'expected_server_revision': expectedServerRevision,
    'request_json': requestJson,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory ArtistWriteJournalEntry.fromRow(Map<String, Object?> row) {
    return ArtistWriteJournalEntry(
      userId: row['user_id'] as String,
      artistId: row['artist_id'] as String,
      outboxId: row['outbox_id'] as String,
      mutationRevision: row['mutation_revision'] as int,
      operation: ArtistWriteJournalOperation.values.byName(
        row['operation'] as String,
      ),
      expectedServerRevision: row['expected_server_revision'] as int?,
      requestJson: row['request_json'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }

  bool sameSnapshot(ArtistWriteJournalEntry other) =>
      userId == other.userId &&
      artistId == other.artistId &&
      outboxId == other.outboxId &&
      mutationRevision == other.mutationRevision &&
      operation == other.operation &&
      expectedServerRevision == other.expectedServerRevision &&
      requestJson == other.requestJson &&
      createdAt == other.createdAt;
}
