import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import 'artist_write_recovery_service.dart';

/// Connects explicit outbound artist mutations to the durable receipt journal.
///
/// This adapter never calls a cloud gateway or acknowledges an outbox entry
/// directly. The recovery service owns both responsibilities.
class OutboundArtistReceiptAdapter {
  const OutboundArtistReceiptAdapter({required this.recovery});

  final ArtistWriteRecoveryService recovery;

  Future<void> pushUpsert({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudArtistRecord artist,
  }) async {
    final prepared = await recovery.prepareUpsert(
      userId: userId,
      entry: entry,
      artist: artist,
    );

    await recovery.submitPrepared(prepared);
  }

  Future<void> pushDelete({
    required String userId,
    required SyncOutboxEntry entry,
  }) async {
    final prepared = await recovery.prepareDelete(userId: userId, entry: entry);

    await recovery.submitPrepared(prepared);
  }
}
