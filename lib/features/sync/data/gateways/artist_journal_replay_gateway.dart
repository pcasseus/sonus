import '../../application/services/artist_receipt_request_codec.dart';
import '../../application/services/cloud_conditional_write_result.dart';
import '../../domain/models/artist_write_journal_entry.dart';

typedef ArtistJournalRpcInvoker =
    Future<Object?> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

class ArtistJournalReplayGateway {
  const ArtistJournalReplayGateway({required this.invokeRpc});

  final ArtistJournalRpcInvoker invokeRpc;

  Future<CloudConditionalWriteResult> replay(
    ArtistWriteJournalEntry entry,
  ) async {
    // Validate every stored argument before making a network request.
    final request = ArtistReceiptRequestCodec.decode(entry);

    final response = await invokeRpc(request.functionName, request.parameters);

    if (response is! List || response.length != 1 || response.single is! Map) {
      throw StateError('Expected exactly one artist receipt RPC row.');
    }

    final result = CloudConditionalWriteResult.fromRpcRow(
      Map<String, dynamic>.from(response.single as Map),
    );

    final successful =
        result.outcome == CloudConditionalWriteOutcome.applied ||
        result.outcome == CloudConditionalWriteOutcome.replayed;

    final expectedRevision = entry.expectedServerRevision == null
        ? 1
        : entry.expectedServerRevision! + 1;

    if (successful && result.serverRevision != expectedRevision) {
      throw StateError('Unexpected artist receipt replay revision.');
    }

    return result;
  }
}
