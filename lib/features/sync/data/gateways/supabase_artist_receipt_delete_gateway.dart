import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_conditional_write_result.dart';

typedef ArtistDeleteReceiptRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Guarded soft-deletion of an artist using a durable mutation receipt.
///
/// This gateway does not acknowledge the local outbox. The coordinator
/// must reconcile the verified server revision before acknowledging.
class SupabaseArtistReceiptDeleteGateway {
  SupabaseArtistReceiptDeleteGateway({required SupabaseClient client})
    : _invokeRpc = ((name, parameters) async =>
          client.rpc(name, params: parameters));

  const SupabaseArtistReceiptDeleteGateway.forTesting(
    ArtistDeleteReceiptRpcInvoker invokeRpc,
  ) : _invokeRpc = invokeRpc;

  static const deleteRpcName = 'delete_artist_with_receipt';

  final ArtistDeleteReceiptRpcInvoker _invokeRpc;

  Future<CloudConditionalWriteResult> deleteArtist({
    required String artistId,
    required int expectedServerRevision,
    required String outboxId,
    required int mutationRevision,
    required DateTime deletedAt,
  }) async {
    if (artistId.trim().isEmpty) {
      throw ArgumentError.value(artistId, 'artistId', 'Must not be blank.');
    }

    if (expectedServerRevision < 1 ||
        expectedServerRevision >= 9223372036854775807) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be a valid positive revision below bigint maximum.',
      );
    }

    if (outboxId.trim().isEmpty) {
      throw ArgumentError.value(outboxId, 'outboxId', 'Must not be blank.');
    }

    if (mutationRevision < 1) {
      throw ArgumentError.value(
        mutationRevision,
        'mutationRevision',
        'Must be positive.',
      );
    }

    final response = await _invokeRpc(deleteRpcName, {
      'p_artist_id': artistId,
      'p_expected_revision': expectedServerRevision,
      'p_outbox_id': outboxId,
      'p_mutation_revision': mutationRevision,
      'p_deleted_at': deletedAt.toUtc().toIso8601String(),
    });

    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError('Expected exactly one artist deletion receipt RPC row.');
    }

    final result = CloudConditionalWriteResult.fromRpcRow(
      Map<String, dynamic>.from(response.single as Map),
    );

    final success =
        result.outcome == CloudConditionalWriteOutcome.applied ||
        result.outcome == CloudConditionalWriteOutcome.replayed;

    if (success && result.serverRevision != expectedServerRevision + 1) {
      throw StateError('Unexpected receipt-aware artist deletion revision.');
    }

    return result;
  }
}
