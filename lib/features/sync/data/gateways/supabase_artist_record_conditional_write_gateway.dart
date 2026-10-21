import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/services/cloud_conditional_write_result.dart';
import '../../domain/models/cloud_records.dart';
import '../contracts/supabase_sync_contract.dart';
import '../mappers/supabase_cloud_record_mapper.dart';

typedef ArtistRecordRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Updates an existing artist's complete synchronized payload.
/// Creation, deletion, and blacklist state are deliberately excluded.
class SupabaseArtistRecordConditionalWriteGateway {
  SupabaseArtistRecordConditionalWriteGateway({required SupabaseClient client})
    : _invokeRpc = ((name, parameters) async =>
          client.rpc(name, params: parameters));

  const SupabaseArtistRecordConditionalWriteGateway.forTesting(
    ArtistRecordRpcInvoker invokeRpc,
  ) : _invokeRpc = invokeRpc;

  static const rpcName = 'update_artist_record_if_revision';

  final ArtistRecordRpcInvoker _invokeRpc;

  Future<CloudConditionalWriteResult> updateArtist({
    required CloudArtistRecord artist,
    required int expectedServerRevision,
  }) async {
    if (artist.id.trim().isEmpty || artist.userId.trim().isEmpty) {
      throw ArgumentError('Artist and account identifiers must not be blank.');
    }

    if (artist.isDeleted) {
      throw ArgumentError('Deleted artists cannot use the update RPC.');
    }

    if (expectedServerRevision < 1) {
      throw ArgumentError.value(
        expectedServerRevision,
        'expectedServerRevision',
        'Must be positive.',
      );
    }

    if (artist.name.trim().isEmpty || artist.canonicalName.trim().isEmpty) {
      throw ArgumentError('Artist names must not be blank.');
    }

    final row = SupabaseCloudRecordMapper.toRow(artist);

    final response = await _invokeRpc(rpcName, <String, dynamic>{
      'p_artist_id': artist.id,
      'p_expected_revision': expectedServerRevision,
      'p_name': artist.name,
      'p_canonical_name': artist.canonicalName,
      'p_header_artwork_id': artist.headerArtworkId,
      'p_top_artists_artwork_id': artist.topArtistsArtworkId,
      'p_metadata_field_states':
          row[SupabaseSyncContract.metadataFieldStatesColumn],
      'p_updated_at': artist.updatedAt.toUtc().toIso8601String(),
    });

    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError(
        'Expected exactly one full artist conditional-write RPC row.',
      );
    }

    final result = CloudConditionalWriteResult.fromRpcRow(
      Map<String, dynamic>.from(response.single as Map),
    );

    if (result.outcome == CloudConditionalWriteOutcome.applied &&
        result.serverRevision != expectedServerRevision + 1) {
      throw StateError('Unexpected applied artist server revision.');
    }

    return result;
  }
}
