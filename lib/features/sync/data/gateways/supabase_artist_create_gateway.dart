import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_conditional_write_result.dart';
import '../../domain/models/cloud_records.dart';
import '../contracts/supabase_sync_contract.dart';
import '../mappers/supabase_cloud_record_mapper.dart';

typedef ArtistCreateRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Inserts an artist without replacing an existing cloud record.
///
/// A conflict is not evidence that local data matches cloud data.
/// Callers must preserve pending work until reconciliation.
class SupabaseArtistCreateGateway {
  SupabaseArtistCreateGateway({required SupabaseClient client})
    : _invokeRpc = ((name, parameters) async =>
          client.rpc(name, params: parameters));

  const SupabaseArtistCreateGateway.forTesting(ArtistCreateRpcInvoker invokeRpc)
    : _invokeRpc = invokeRpc;

  static const rpcName = 'create_artist_if_absent';

  final ArtistCreateRpcInvoker _invokeRpc;

  Future<CloudConditionalWriteResult> createArtist({
    required CloudArtistRecord artist,
  }) async {
    if (artist.id.trim().isEmpty || artist.userId.trim().isEmpty) {
      throw ArgumentError('Artist and account IDs must not be blank.');
    }

    if (artist.name.trim().isEmpty || artist.canonicalName.trim().isEmpty) {
      throw ArgumentError('Artist names must not be blank.');
    }

    if (artist.isDeleted) {
      throw ArgumentError('Cannot create an artist tombstone.');
    }

    final row = SupabaseCloudRecordMapper.toRow(artist);

    final response = await _invokeRpc(rpcName, <String, dynamic>{
      'p_artist_id': artist.id,
      'p_name': artist.name,
      'p_canonical_name': artist.canonicalName,
      'p_header_artwork_id': artist.headerArtworkId,
      'p_top_artists_artwork_id': artist.topArtistsArtworkId,
      'p_metadata_field_states':
          row[SupabaseSyncContract.metadataFieldStatesColumn],
      'p_created_at': artist.createdAt.toUtc().toIso8601String(),
      'p_updated_at': artist.updatedAt.toUtc().toIso8601String(),
    });

    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError('Expected exactly one artist creation RPC row.');
    }

    final result = CloudConditionalWriteResult.fromRpcRow(
      Map<String, dynamic>.from(response.single as Map),
    );

    // A newly inserted artist starts at server revision 1.
    if (result.outcome == CloudConditionalWriteOutcome.applied &&
        result.serverRevision != 1) {
      throw StateError('New artist must begin at server revision 1.');
    }

    return result;
  }
}
