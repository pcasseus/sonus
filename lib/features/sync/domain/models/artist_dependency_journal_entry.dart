import 'dart:convert';

class ArtistDependencyJournalEntry {
  ArtistDependencyJournalEntry({
    required this.userId,
    required this.artistId,
    required this.requestId,
    required this.requestJson,
    required this.createdAt,
    this.mutationRevision = 1,
  }) {
    if (userId.trim().isEmpty ||
        userId != userId.trim() ||
        artistId.trim().isEmpty ||
        requestId.trim().isEmpty ||
        mutationRevision != 1 ||
        !createdAt.isUtc) {
      throw ArgumentError('Invalid artist dependency journal identity.');
    }

    final dynamic decoded;

    try {
      decoded = jsonDecode(requestJson);
    } on FormatException {
      throw ArgumentError('Invalid dependency request JSON.');
    }

    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['function_name'] != 'create_artist_with_receipt' ||
        decoded['parameters'] is! Map) {
      throw ArgumentError('Invalid dependency RPC envelope.');
    }

    final parameters = decoded['parameters'] as Map;

    const requiredKeys = <String>{
      'p_artist_id',
      'p_outbox_id',
      'p_mutation_revision',
      'p_name',
      'p_canonical_name',
      'p_header_artwork_id',
      'p_top_artists_artwork_id',
      'p_metadata_field_states',
      'p_created_at',
      'p_updated_at',
    };

    if (parameters.keys.toSet().difference(requiredKeys).isNotEmpty ||
        requiredKeys.difference(parameters.keys.toSet()).isNotEmpty ||
        parameters['p_artist_id'] != artistId ||
        parameters['p_outbox_id'] != requestId ||
        parameters['p_mutation_revision'] != mutationRevision ||
        parameters['p_name'] is! String ||
        (parameters['p_name'] as String).trim().isEmpty ||
        parameters['p_canonical_name'] is! String ||
        (parameters['p_canonical_name'] as String).trim().isEmpty) {
      throw ArgumentError('Dependency RPC identity or payload mismatch.');
    }

    for (final key in ['p_created_at', 'p_updated_at']) {
      final value = parameters[key];
      if (value is! String || DateTime.tryParse(value) == null) {
        throw ArgumentError('Invalid dependency timestamp: $key.');
      }
    }

    for (final key in ['p_header_artwork_id', 'p_top_artists_artwork_id']) {
      final value = parameters[key];
      if (value != null && value is! String) {
        throw ArgumentError('Invalid dependency artwork reference.');
      }
    }

    final metadata = parameters['p_metadata_field_states'];
    if (metadata != null && metadata is! List) {
      throw ArgumentError('Invalid dependency metadata states.');
    }
  }

  final String userId;
  final String artistId;
  final String requestId;
  final int mutationRevision;
  final String requestJson;
  final DateTime createdAt;

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'artist_id': artistId,
    'request_id': requestId,
    'mutation_revision': mutationRevision,
    'request_json': requestJson,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory ArtistDependencyJournalEntry.fromRow(Map<String, Object?> row) {
    return ArtistDependencyJournalEntry(
      userId: row['user_id'] as String,
      artistId: row['artist_id'] as String,
      requestId: row['request_id'] as String,
      mutationRevision: row['mutation_revision'] as int,
      requestJson: row['request_json'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }

  bool sameSnapshot(ArtistDependencyJournalEntry other) =>
      userId == other.userId &&
      artistId == other.artistId &&
      requestId == other.requestId &&
      mutationRevision == other.mutationRevision &&
      requestJson == other.requestJson &&
      createdAt == other.createdAt;
}
