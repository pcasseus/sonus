import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_conditional_write_result.dart';
import '../../domain/models/cloud_records.dart';
import '../contracts/supabase_sync_contract.dart';
import '../mappers/supabase_cloud_record_mapper.dart';

typedef ArtistReceiptRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Receipt-aware RPC gateway for explicit artist outbox upserts.
///
/// Dependency creation deliberately remains on its separate insert-only path.
class SupabaseArtistReceiptWriteGateway {
  SupabaseArtistReceiptWriteGateway({required SupabaseClient client})
    : _invokeRpc = ((name, parameters) async =>
          client.rpc(name, params: parameters));

  const SupabaseArtistReceiptWriteGateway.forTesting(
    ArtistReceiptRpcInvoker invokeRpc,
  ) : _invokeRpc = invokeRpc;

  static const createRpcName = 'create_artist_with_receipt';
  static const updateRpcName = 'update_artist_record_with_receipt';

  final ArtistReceiptRpcInvoker _invokeRpc;

  Future<CloudConditionalWriteResult> createArtist({
    required CloudArtistRecord artist,
    required String outboxId,
    required int mutationRevision,
  }) async {
    _validate(artist, outboxId, mutationRevision);

    final row = SupabaseCloudRecordMapper.toRow(artist);

    final response = await _invokeRpc(createRpcName, {
      'p_artist_id': artist.id,
      'p_outbox_id': outboxId,
      'p_mutation_revision': mutationRevision,
      'p_name': artist.name,
      'p_canonical_name': artist.canonicalName,
      'p_header_artwork_id': artist.headerArtworkId,
      'p_top_artists_artwork_id': artist.topArtistsArtworkId,
      'p_metadata_field_states':
          row[SupabaseSyncContract.metadataFieldStatesColumn],
      'p_created_at': artist.createdAt.toUtc().toIso8601String(),
      'p_updated_at': artist.updatedAt.toUtc().toIso8601String(),
    });

    final result = _parse(response);

    if (_isSuccess(result) && result.serverRevision != 1) {
      throw StateError('Artist creation must return server revision 1.');
    }

    return result;
  }

  Future<CloudConditionalWriteResult> updateArtist({
    required CloudArtistRecord artist,
    required int expectedServerRevision,
    required String outboxId,
    required int mutationRevision,
  }) async {
    _validate(artist, outboxId, mutationRevision);

    if (expectedServerRevision < 1) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be positive.',
      );
    }

    final row = SupabaseCloudRecordMapper.toRow(artist);

    final response = await _invokeRpc(updateRpcName, {
      'p_artist_id': artist.id,
      'p_expected_revision': expectedServerRevision,
      'p_outbox_id': outboxId,
      'p_mutation_revision': mutationRevision,
      'p_name': artist.name,
      'p_canonical_name': artist.canonicalName,
      'p_header_artwork_id': artist.headerArtworkId,
      'p_top_artists_artwork_id': artist.topArtistsArtworkId,
      'p_metadata_field_states':
          row[SupabaseSyncContract.metadataFieldStatesColumn],
      'p_updated_at': artist.updatedAt.toUtc().toIso8601String(),
    });

    final result = _parse(response);

    if (_isSuccess(result) &&
        result.serverRevision != expectedServerRevision + 1) {
      throw StateError('Unexpected receipt-aware artist update revision.');
    }

    return result;
  }

  static void _validate(
    CloudArtistRecord artist,
    String outboxId,
    int mutationRevision,
  ) {
    if (artist.id.trim().isEmpty ||
        artist.userId.trim().isEmpty ||
        artist.name.trim().isEmpty ||
        artist.canonicalName.trim().isEmpty ||
        artist.isDeleted) {
      throw ArgumentError('Invalid artist for receipt-aware upsert.');
    }

    if (outboxId.trim().isEmpty || mutationRevision < 1) {
      throw ArgumentError('Invalid artist outbox mutation identity.');
    }
  }

  static bool _isSuccess(CloudConditionalWriteResult result) =>
      result.outcome == CloudConditionalWriteOutcome.applied ||
      result.outcome == CloudConditionalWriteOutcome.replayed;

  static CloudConditionalWriteResult _parse(Object? response) {
    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError('Expected exactly one artist receipt RPC row.');
    }

    return CloudConditionalWriteResult.fromRpcRow(
      Map<String, dynamic>.from(response.single as Map),
    );
  }
}
