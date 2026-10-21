import 'dart:async';

import '../../domain/models/artist_write_journal_entry.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import '../../data/gateways/artist_journal_replay_gateway.dart';
import 'artist_receipt_request_codec.dart';
import 'cloud_conditional_write_result.dart';
import 'sync_mutation_runner.dart';

/// Durable receipt-aware artist write execution.
///
/// A prepared journal entry must commit locally before any cloud request.
/// Unresolved entries are recovered from the stored RPC snapshot, never
/// reconstructed from the current artist or outbox payload.
class ArtistWriteRecoveryService {
  ArtistWriteRecoveryService({
    required this.mutationRunner,
    required this.replayGateway,
    required this.now,
  });

  final SyncMutationRunner mutationRunner;
  final ArtistJournalReplayGateway replayGateway;
  final DateTime Function() now;

  // Prevent duplicate simultaneous submissions through this instance.
  // Server-side receipts remain authoritative across app processes.
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, ArtistWriteJournalEntry> _inFlightEntries = {};

  String _flightKey(ArtistWriteJournalEntry entry) =>
      '${entry.userId}:${entry.artistId}';

  Future<ArtistWriteJournalEntry> prepareUpsert({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudArtistRecord artist,
  }) {
    _validateEntry(
      userId: userId,
      entry: entry,
      operation: SyncOutboxOperation.upsert,
    );

    if (artist.id != entry.entityId ||
        artist.userId != userId ||
        artist.isDeleted) {
      throw StateError('Artist snapshot does not match the outbox mutation.');
    }

    return mutationRunner.run<ArtistWriteJournalEntry>((context) async {
      final journals = context.artistWriteJournalRepository;
      final baselines = context.cloudRevisionBaselineRepository;

      if (journals == null || baselines == null) {
        throw StateError('Recovery repositories are unavailable.');
      }

      final unresolved = await journals.findUnresolved(
        userId: userId,
        artistId: entry.entityId,
      );

      // The older receipt takes priority even if the outbox has changed.
      if (unresolved != null) {
        ArtistReceiptRequestCodec.decode(unresolved);
        return unresolved;
      }

      // A dependency creation may already have committed remotely.
      // Reconcile its original receipt before preparing another write.
      final dependencies = context.artistDependencyJournalRepository;

      if (dependencies == null) {
        throw StateError('Dependency receipt journal repository unavailable.');
      }

      final unresolvedDependency = await dependencies.findUnresolved(
        userId: userId,
        artistId: entry.entityId,
      );

      if (unresolvedDependency != null) {
        throw StateError(
          'Older artist dependency receipt must be reconciled first.',
        );
      }

      await _verifyPending(context: context, entry: entry);

      final revision = await baselines.getRevision(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.entityId,
      );

      final prepared = ArtistReceiptRequestCodec.forUpsert(
        artist: artist,
        outboxId: entry.id,
        mutationRevision: entry.mutationRevision,
        expectedServerRevision: revision,
        preparedAt: now().toUtc(),
      );

      await journals.prepare(prepared);
      return prepared;
    });
  }

  Future<ArtistWriteJournalEntry> prepareDelete({
    required String userId,
    required SyncOutboxEntry entry,
  }) {
    _validateEntry(
      userId: userId,
      entry: entry,
      operation: SyncOutboxOperation.delete,
    );

    return mutationRunner.run<ArtistWriteJournalEntry>((context) async {
      final journals = context.artistWriteJournalRepository;
      final baselines = context.cloudRevisionBaselineRepository;

      if (journals == null || baselines == null) {
        throw StateError('Recovery repositories are unavailable.');
      }

      final unresolved = await journals.findUnresolved(
        userId: userId,
        artistId: entry.entityId,
      );

      if (unresolved != null) {
        ArtistReceiptRequestCodec.decode(unresolved);
        return unresolved;
      }

      // A dependency creation may already have committed remotely.
      // Reconcile its original receipt before preparing another write.
      final dependencies = context.artistDependencyJournalRepository;

      if (dependencies == null) {
        throw StateError('Dependency receipt journal repository unavailable.');
      }

      final unresolvedDependency = await dependencies.findUnresolved(
        userId: userId,
        artistId: entry.entityId,
      );

      if (unresolvedDependency != null) {
        throw StateError(
          'Older artist dependency receipt must be reconciled first.',
        );
      }

      await _verifyPending(context: context, entry: entry);

      final revision = await baselines.getRevision(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.entityId,
      );

      if (revision == null) {
        throw StateError(
          'Artist deletion requires a reconciled cloud baseline.',
        );
      }

      final prepared = ArtistReceiptRequestCodec.forDelete(
        userId: userId,
        artistId: entry.entityId,
        outboxId: entry.id,
        mutationRevision: entry.mutationRevision,
        expectedServerRevision: revision,
        deletedAt: entry.updatedAt,
        preparedAt: now().toUtc(),
      );

      await journals.prepare(prepared);
      return prepared;
    });
  }

  /// Recover all unresolved writes before ordinary outbox processing.
  Future<void> recoverUnresolved(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }

    final entries = await mutationRunner.run<List<ArtistWriteJournalEntry>>((
      context,
    ) async {
      final journals = context.artistWriteJournalRepository;
      if (journals == null) {
        throw StateError('Recovery journal repository unavailable.');
      }
      return journals.findUnresolvedForUser(userId);
    });

    for (final entry in entries) {
      await submitPrepared(entry);
    }
  }

  /// Submit only a previously committed journal snapshot.
  Future<void> submitPrepared(ArtistWriteJournalEntry entry) {
    final key = _flightKey(entry);
    final existing = _inFlight[key];

    if (existing != null) {
      final current = _inFlightEntries[key];

      if (current == null || !current.sameSnapshot(entry)) {
        return Future<void>.error(
          StateError('Different artist receipt is already in flight.'),
        );
      }

      return existing;
    }

    final completion = Completer<void>();
    _inFlight[key] = completion.future;
    _inFlightEntries[key] = entry;

    Future<void> execute() async {
      try {
        await _submitPreparedOnce(entry);
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      } finally {
        _inFlight.remove(key);
        _inFlightEntries.remove(key);
      }
    }

    unawaited(execute());
    return completion.future;
  }

  Future<void> _submitPreparedOnce(ArtistWriteJournalEntry entry) async {
    final present = await mutationRunner.run<bool>((context) async {
      final journals = context.artistWriteJournalRepository;
      if (journals == null) {
        throw StateError('Recovery journal repository unavailable.');
      }

      final stored = await journals.findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (stored == null || !stored.sameSnapshot(entry)) {
        throw StateError('Artist request was not durably prepared.');
      }

      ArtistReceiptRequestCodec.decode(stored);
      return true;
    });

    if (!present) {
      throw StateError('Artist request is not durable.');
    }

    // No SQLite transaction is held during this network call.
    final result = await replayGateway.replay(entry);

    if (result.outcome != CloudConditionalWriteOutcome.applied &&
        result.outcome != CloudConditionalWriteOutcome.replayed) {
      // Preserve the original request. The caller may reconcile the
      // conflict separately, but must not silently discard its receipt.
      throw StateError('Unresolved artist cloud receipt: ${result.outcome}.');
    }

    final revision = result.serverRevision;
    if (revision == null || revision < 1) {
      throw StateError('Verified artist receipt has no server revision.');
    }

    await mutationRunner.run<void>((context) async {
      final journals = context.artistWriteJournalRepository;
      final baselines = context.cloudRevisionBaselineRepository;

      if (journals == null || baselines == null) {
        throw StateError('Recovery repositories unavailable.');
      }

      final stored = await journals.findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (stored == null || !stored.sameSnapshot(entry)) {
        throw StateError('Journal changed during artist receipt replay.');
      }

      final baseline = await baselines.getRevision(
        userId: entry.userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.artistId,
      );

      if (baseline != null && baseline > revision) {
        throw StateError('Local baseline is newer than the recovered receipt.');
      }

      await baselines.saveObservedRevision(
        userId: entry.userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.artistId,
        serverRevision: revision,
      );

      await context.localSyncRepository.markProcessed(
        userId: entry.userId,
        outboxEntryId: entry.outboxId,
        expectedRevision: entry.mutationRevision,
        expectedOperation: entry.operation == ArtistWriteJournalOperation.delete
            ? SyncOutboxOperation.delete
            : SyncOutboxOperation.upsert,
      );

      final removed = await journals.removeVerified(entry);
      if (removed != 1) {
        throw StateError('Verified journal removal failed.');
      }
    });
  }

  static Future<void> _verifyPending({
    required dynamic context,
    required SyncOutboxEntry entry,
  }) async {
    final pending = await context.localSyncRepository.getPending(entry.userId);

    final matches = pending.where(
      (candidate) =>
          candidate.id == entry.id &&
          candidate.userId == entry.userId &&
          candidate.entityType == CloudDataEntity.artist &&
          candidate.entityId == entry.entityId &&
          candidate.operation == entry.operation &&
          candidate.mutationRevision == entry.mutationRevision,
    );

    if (matches.length != 1) {
      throw StateError('Artist outbox mutation changed before preparation.');
    }
  }

  static void _validateEntry({
    required String userId,
    required SyncOutboxEntry entry,
    required SyncOutboxOperation operation,
  }) {
    if (userId.trim().isEmpty ||
        entry.userId != userId ||
        entry.id.trim().isEmpty ||
        entry.entityId.trim().isEmpty ||
        entry.entityType != CloudDataEntity.artist ||
        entry.operation != operation ||
        entry.mutationRevision < 1) {
      throw StateError('Invalid artist recovery outbox identity.');
    }
  }
}
