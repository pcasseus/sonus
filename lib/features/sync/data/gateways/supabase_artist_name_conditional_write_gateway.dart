import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/artist_name_conditional_write_gateway.dart';
import '../../application/services/cloud_conditional_write_result.dart';

typedef ArtistConditionalRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Supabase adapter for the name-only proof-of-concept RPC.
/// It never performs a fallback unconditional upsert.
class SupabaseArtistNameConditionalWriteGateway
    implements ArtistNameConditionalWriteGateway {
  SupabaseArtistNameConditionalWriteGateway({required SupabaseClient client})
    : _invokeRpc = ((name, parameters) async =>
          client.rpc(name, params: parameters));

  const SupabaseArtistNameConditionalWriteGateway.forTesting(
    ArtistConditionalRpcInvoker invokeRpc,
  ) : _invokeRpc = invokeRpc;

  static const rpcName = 'update_artist_name_if_revision';

  final ArtistConditionalRpcInvoker _invokeRpc;

  @override
  Future<CloudConditionalWriteResult> updateArtistName({
    required String artistId,
    required int expectedServerRevision,
    required String name,
    required String canonicalName,
    required DateTime updatedAt,
  }) async {
    if (artistId.trim().isEmpty) {
      throw ArgumentError.value(artistId, 'artistId', 'Must not be blank.');
    }
    if (expectedServerRevision < 1) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be positive.',
      );
    }
    if (name.trim().isEmpty || canonicalName.trim().isEmpty) {
      throw ArgumentError('Artist names must not be blank.');
    }

    final response = await _invokeRpc(rpcName, <String, dynamic>{
      'p_artist_id': artistId,
      'p_expected_revision': expectedServerRevision,
      'p_name': name,
      'p_canonical_name': canonicalName,
      'p_updated_at': updatedAt.toUtc().toIso8601String(),
    });

    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError(
        'Expected exactly one artist conditional-write RPC row.',
      );
    }

    final row = Map<String, dynamic>.from(response.single as Map);
    final result = CloudConditionalWriteResult.fromRpcRow(row);

    if (result.outcome == CloudConditionalWriteOutcome.applied &&
        result.serverRevision != expectedServerRevision + 1) {
      throw StateError('Unexpected applied artist server revision.');
    }

    return result;
  }
}
