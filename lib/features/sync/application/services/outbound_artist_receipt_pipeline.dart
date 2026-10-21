import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'artist_dependency_recovery_service.dart';
import 'artist_write_recovery_service.dart';
import 'outbound_artist_receipt_adapter.dart';
import 'outbound_sync_processor.dart';
import 'sync_mutation_runner.dart';

/// Composes durable explicit artist writes, restart recovery, and
/// safeguards for dependency-only artist creation.
///
/// This class does not own a cloud connection. The recovery service
/// dispatches immutable journal requests; dependency creation retains
/// its separate insert-only implementation.
class OutboundArtistReceiptPipeline {
  const OutboundArtistReceiptPipeline({
    required this.recovery,
    this.dependencyRecovery,
    required this.mutationRunner,
    required this.ensureDependency,
  });

  final ArtistWriteRecoveryService recovery;
  final ArtistDependencyRecoveryService? dependencyRecovery;
  final SyncMutationRunner mutationRunner;
  final EnsureArtistDependency ensureDependency;

  Future<void> pushUpsert({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudArtistRecord artist,
  }) {
    return OutboundArtistReceiptAdapter(
      recovery: recovery,
    ).pushUpsert(userId: userId, entry: entry, artist: artist);
  }

  Future<void> pushDelete({
    required String userId,
    required SyncOutboxEntry entry,
  }) {
    return OutboundArtistReceiptAdapter(
      recovery: recovery,
    ).pushDelete(userId: userId, entry: entry);
  }

  /// Intended to run before the ordinary outbound outbox is read.
  Future<void> recover(String userId) async {
    // Recover durable dependency receipts before explicit writes.
    // Any failure stops ordinary outbound processing.
    await dependencyRecovery?.recoverUnresolved(userId);
    await recovery.recoverUnresolved(userId);
  }

  /// Fail closed when this artist has an unfinished explicit mutation.
  ///
  /// This prevents the dependency path from deliberately bypassing
  /// an already-present journal or pending artist mutation.
  ///
  /// The check and network operation are not one atomic operation.
  /// Production cutover additionally requires serialization against
  /// newly arriving explicit mutations and dependency requests.
  Future<void> guardedDependency({
    required String userId,
    required CloudArtistRecord artist,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty ||
        owner != userId ||
        artist.userId != owner ||
        artist.id.trim().isEmpty ||
        artist.isDeleted) {
      throw StateError('Invalid artist dependency ownership or identity.');
    }

    // Check immediately before making the insert-only cloud request.
    await _rejectPendingArtistWork(userId: owner, artistId: artist.id);

    await ensureDependency(userId: owner, artist: artist);

    // A local edit may have committed while the cloud request was
    // in flight. Fail closed so dependent album/song uploads cannot
    // continue under an unverified artist state.
    //
    // This does not roll back the cloud insert or make the request
    // atomic with local mutations. Production cutover still requires
    // a stronger coordination protocol.
    await _rejectPendingArtistWork(userId: owner, artistId: artist.id);
  }

  Future<void> _rejectPendingArtistWork({
    required String userId,
    required String artistId,
  }) async {
    final blocked = await mutationRunner.run<bool>((context) async {
      final journals = context.artistWriteJournalRepository;

      if (journals == null) {
        throw StateError('Artist receipt journal repository unavailable.');
      }

      final unresolved = await journals.findUnresolved(
        userId: userId,
        artistId: artistId,
      );

      if (unresolved != null) {
        return true;
      }

      final pending = await context.localSyncRepository.getPending(userId);

      return pending.any(
        (entry) =>
            entry.entityType == CloudDataEntity.artist &&
            entry.entityId == artistId,
      );
    });

    if (blocked) {
      throw StateError(
        'Artist dependency deferred until its explicit '
        'mutation and durable receipt are reconciled.',
      );
    }
  }
}
