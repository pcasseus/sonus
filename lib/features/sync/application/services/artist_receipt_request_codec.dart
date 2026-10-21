import 'dart:convert';

import '../../domain/models/artist_write_journal_entry.dart';
import '../../domain/models/cloud_records.dart';
import '../../data/mappers/supabase_cloud_record_mapper.dart';

class ArtistReceiptRpcRequest {
  const ArtistReceiptRpcRequest({
    required this.functionName,
    required this.parameters,
  });

  final String functionName;
  final Map<String, dynamic> parameters;
}

abstract final class ArtistReceiptRequestCodec {
  static const createFunction = 'create_artist_with_receipt';
  static const updateFunction = 'update_artist_record_with_receipt';
  static const deleteFunction = 'delete_artist_with_receipt';

  static const _createKeys = {
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

  static const _updateKeys = {
    'p_artist_id',
    'p_expected_revision',
    'p_outbox_id',
    'p_mutation_revision',
    'p_name',
    'p_canonical_name',
    'p_header_artwork_id',
    'p_top_artists_artwork_id',
    'p_metadata_field_states',
    'p_updated_at',
  };

  static const _deleteKeys = {
    'p_artist_id',
    'p_expected_revision',
    'p_outbox_id',
    'p_mutation_revision',
    'p_deleted_at',
  };

  static ArtistWriteJournalEntry forUpsert({
    required CloudArtistRecord artist,
    required String outboxId,
    required int mutationRevision,
    required int? expectedServerRevision,
    required DateTime preparedAt,
  }) {
    if (artist.id.trim().isEmpty ||
        artist.userId.trim().isEmpty ||
        artist.name.trim().isEmpty ||
        artist.canonicalName.trim().isEmpty ||
        artist.isDeleted) {
      throw ArgumentError('Invalid artist for receipt preparation.');
    }

    if (expectedServerRevision != null &&
        (expectedServerRevision < 1 ||
            expectedServerRevision >= 9223372036854775807)) {
      throw ArgumentError('Invalid expected artist revision.');
    }

    final row = SupabaseCloudRecordMapper.toRow(artist);
    final metadata = row['metadata_field_states'];

    final parameters = <String, dynamic>{
      'p_artist_id': artist.id,
      'p_outbox_id': outboxId,
      'p_mutation_revision': mutationRevision,
      'p_name': artist.name,
      'p_canonical_name': artist.canonicalName,
      'p_header_artwork_id': artist.headerArtworkId,
      'p_top_artists_artwork_id': artist.topArtistsArtworkId,
      'p_metadata_field_states': metadata,
      if (expectedServerRevision == null)
        'p_created_at': artist.createdAt.toUtc().toIso8601String(),
      'p_expected_revision': ?expectedServerRevision,
      'p_updated_at': artist.updatedAt.toUtc().toIso8601String(),
    };

    return _make(
      userId: artist.userId,
      artistId: artist.id,
      outboxId: outboxId,
      mutationRevision: mutationRevision,
      operation: expectedServerRevision == null
          ? ArtistWriteJournalOperation.create
          : ArtistWriteJournalOperation.update,
      expectedServerRevision: expectedServerRevision,
      functionName: expectedServerRevision == null
          ? createFunction
          : updateFunction,
      parameters: parameters,
      preparedAt: preparedAt,
    );
  }

  static ArtistWriteJournalEntry forDelete({
    required String userId,
    required String artistId,
    required String outboxId,
    required int mutationRevision,
    required int expectedServerRevision,
    required DateTime deletedAt,
    required DateTime preparedAt,
  }) {
    if (expectedServerRevision < 1 ||
        expectedServerRevision >= 9223372036854775807) {
      throw ArgumentError('Invalid expected deletion revision.');
    }

    return _make(
      userId: userId,
      artistId: artistId,
      outboxId: outboxId,
      mutationRevision: mutationRevision,
      operation: ArtistWriteJournalOperation.delete,
      expectedServerRevision: expectedServerRevision,
      functionName: deleteFunction,
      parameters: {
        'p_artist_id': artistId,
        'p_expected_revision': expectedServerRevision,
        'p_outbox_id': outboxId,
        'p_mutation_revision': mutationRevision,
        'p_deleted_at': deletedAt.toUtc().toIso8601String(),
      },
      preparedAt: preparedAt,
    );
  }

  static ArtistWriteJournalEntry _make({
    required String userId,
    required String artistId,
    required String outboxId,
    required int mutationRevision,
    required ArtistWriteJournalOperation operation,
    required int? expectedServerRevision,
    required String functionName,
    required Map<String, dynamic> parameters,
    required DateTime preparedAt,
  }) {
    final entry = ArtistWriteJournalEntry(
      userId: userId,
      artistId: artistId,
      outboxId: outboxId,
      mutationRevision: mutationRevision,
      operation: operation,
      expectedServerRevision: expectedServerRevision,
      requestJson: jsonEncode({
        'function_name': functionName,
        'parameters': parameters,
      }),
      createdAt: preparedAt.toUtc(),
    );

    decode(entry);
    return entry;
  }

  static ArtistReceiptRpcRequest decode(ArtistWriteJournalEntry entry) {
    final decoded = jsonDecode(entry.requestJson);

    if (decoded is! Map ||
        decoded.length != 2 ||
        !decoded.containsKey('function_name') ||
        !decoded.containsKey('parameters') ||
        decoded['function_name'] is! String ||
        decoded['parameters'] is! Map) {
      throw StateError('Invalid stored artist RPC envelope.');
    }

    final functionName = decoded['function_name'] as String;
    final parameters = Map<String, dynamic>.from(decoded['parameters'] as Map);

    final expectedFunction = switch (entry.operation) {
      ArtistWriteJournalOperation.create => createFunction,
      ArtistWriteJournalOperation.update => updateFunction,
      ArtistWriteJournalOperation.delete => deleteFunction,
    };

    final expectedKeys = switch (entry.operation) {
      ArtistWriteJournalOperation.create => _createKeys,
      ArtistWriteJournalOperation.update => _updateKeys,
      ArtistWriteJournalOperation.delete => _deleteKeys,
    };

    if (functionName != expectedFunction ||
        parameters.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(parameters.keys.toSet()).isNotEmpty ||
        parameters['p_artist_id'] != entry.artistId ||
        parameters['p_outbox_id'] != entry.outboxId ||
        parameters['p_mutation_revision'] != entry.mutationRevision) {
      throw StateError('Stored artist RPC identity or shape mismatch.');
    }

    if (entry.operation != ArtistWriteJournalOperation.create &&
        parameters['p_expected_revision'] != entry.expectedServerRevision) {
      throw StateError('Stored artist RPC revision mismatch.');
    }

    if (entry.operation != ArtistWriteJournalOperation.delete) {
      final name = parameters['p_name'];
      final canonicalName = parameters['p_canonical_name'];
      final metadata = parameters['p_metadata_field_states'];

      if (name is! String ||
          name.trim().isEmpty ||
          canonicalName is! String ||
          canonicalName.trim().isEmpty ||
          (metadata != null && metadata is! List)) {
        throw StateError('Invalid stored artist RPC payload.');
      }

      for (final key in ['p_header_artwork_id', 'p_top_artists_artwork_id']) {
        final value = parameters[key];
        if (value != null && value is! String) {
          throw StateError('Invalid artist artwork RPC argument.');
        }
      }
    }

    final timestamps = switch (entry.operation) {
      ArtistWriteJournalOperation.create => ['p_created_at', 'p_updated_at'],
      ArtistWriteJournalOperation.update => ['p_updated_at'],
      ArtistWriteJournalOperation.delete => ['p_deleted_at'],
    };

    for (final key in timestamps) {
      final value = parameters[key];
      if (value is! String || DateTime.tryParse(value) == null) {
        throw StateError('Invalid stored RPC timestamp: $key.');
      }
    }

    return ArtistReceiptRpcRequest(
      functionName: functionName,
      parameters: parameters,
    );
  }
}
