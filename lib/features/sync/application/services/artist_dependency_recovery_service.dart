import 'dart:async';

import '../../domain/models/artist_dependency_journal_entry.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';
import 'artist_receipt_request_codec.dart';
import 'cloud_conditional_write_result.dart';
import 'sync_mutation_runner.dart';

typedef ReplayArtistDependencyReceipt =
    Future<CloudConditionalWriteResult> Function(
      ArtistDependencyJournalEntry entry,
    );

/// Durable receipt recovery for dependency-only artist creation.
///
/// This path never acknowledges an explicit artist outbox mutation.
class ArtistDependencyRecoveryService {
  ArtistDependencyRecoveryService({
    required this.mutationRunner,
    required this.replayReceipt,
    required this.generateRequestId,
    required this.now,
  });

  final SyncMutationRunner mutationRunner;
  final ReplayArtistDependencyReceipt replayReceipt;
  final String Function() generateRequestId;
  final DateTime Function() now;

  final Map<String, Future<void>> _inFlight = {};
  final Map<String, ArtistDependencyJournalEntry> _inFlightEntries = {};

  String _flightKey(ArtistDependencyJournalEntry entry) =>
      '${entry.userId}:${entry.artistId}';

  /// Returns null when the artist already has a reconciled baseline.
  ///
  /// An older unresolved dependency takes priority over current edits.
  Future<ArtistDependencyJournalEntry?> prepare({
    required String userId,
    required CloudArtistRecord artist,
  }) {
    if (userId.trim().isEmpty ||
        userId != userId.trim() ||
        artist.userId != userId ||
        artist.id.trim().isEmpty ||
        artist.isDeleted) {
      throw StateError('Invalid artist dependency ownership or identity.');
    }

    return mutationRunner.run<ArtistDependencyJournalEntry?>((context) async {
      final dependencies = context.artistDependencyJournalRepository;
      final explicitWrites = context.artistWriteJournalRepository;
      final baselines = context.cloudRevisionBaselineRepository;

      if (dependencies == null || explicitWrites == null || baselines == null) {
        throw StateError('Dependency recovery repositories unavailable.');
      }

      final unresolved = await dependencies.findUnresolved(
        userId: userId,
        artistId: artist.id,
      );

      if (unresolved != null) {
        // Never regenerate an already-issued cloud request.
        return unresolved;
      }

      final revision = await baselines.getRevision(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artist.id,
      );

      if (revision != null) {
        if (revision < 1) {
          throw StateError('Invalid existing artist baseline.');
        }
        return null;
      }

      final explicit = await explicitWrites.findUnresolved(
        userId: userId,
        artistId: artist.id,
      );

      if (explicit != null) {
        throw StateError('Explicit artist receipt must be recovered first.');
      }

      final pending = await context.localSyncRepository.getPending(userId);

      if (pending.any(
        (entry) =>
            entry.entityType == CloudDataEntity.artist &&
            entry.entityId == artist.id,
      )) {
        throw StateError('Explicit artist mutation must be reconciled first.');
      }

      final id = generateRequestId();
      final preparedAt = now().toUtc();

      if (id.trim().isEmpty || id != id.trim()) {
        throw StateError('Invalid generated dependency receipt identity.');
      }

      final receipt = ArtistReceiptRequestCodec.forUpsert(
        artist: artist,
        outboxId: id,
        mutationRevision: 1,
        expectedServerRevision: null,
        preparedAt: preparedAt,
      );

      final dependency = ArtistDependencyJournalEntry(
        userId: userId,
        artistId: artist.id,
        requestId: id,
        mutationRevision: 1,
        requestJson: receipt.requestJson,
        createdAt: preparedAt,
      );

      await dependencies.prepare(dependency);
      return dependency;
    });
  }

  Future<void> ensure({
    required String userId,
    required CloudArtistRecord artist,
  }) async {
    final entry = await prepare(userId: userId, artist: artist);
    if (entry != null) {
      await submitPrepared(entry);
    }
  }

  /// Recover a durable request without rebuilding its artist snapshot.
  Future<void> recoverUnresolved(String userId) async {
    if (userId.trim().isEmpty || userId != userId.trim()) {
      throw ArgumentError.value(userId, 'userId');
    }

    final entries = await mutationRunner.run((context) async {
      final repository = context.artistDependencyJournalRepository;
      if (repository == null) {
        throw StateError('Dependency recovery repository unavailable.');
      }
      return repository.findUnresolvedForUser(userId);
    });

    for (final entry in entries) {
      await submitPrepared(entry);
    }
  }

  Future<void> submitPrepared(ArtistDependencyJournalEntry entry) {
    final key = _flightKey(entry);
    final existing = _inFlight[key];

    if (existing != null) {
      final active = _inFlightEntries[key];
      if (active == null || !active.sameSnapshot(entry)) {
        return Future<void>.error(
          StateError('Different dependency request already in flight.'),
        );
      }
      return existing;
    }

    final completion = Completer<void>();
    _inFlight[key] = completion.future;
    _inFlightEntries[key] = entry;

    Future<void> execute() async {
      try {
        await _submitOnce(entry);
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

  Future<void> _submitOnce(ArtistDependencyJournalEntry entry) async {
    // The journal must be committed before any network call.
    await mutationRunner.run<void>((context) async {
      final repository = context.artistDependencyJournalRepository;
      if (repository == null) {
        throw StateError('Dependency recovery repository unavailable.');
      }

      final stored = await repository.findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (stored == null || !stored.sameSnapshot(entry)) {
        throw StateError('Dependency request was not durably prepared.');
      }
    });

    // No SQLite transaction is held during the remote call.
    final result = await replayReceipt(entry);

    if (result.outcome != CloudConditionalWriteOutcome.applied &&
        result.outcome != CloudConditionalWriteOutcome.replayed) {
      throw StateError(
        'Dependency cloud receipt is unresolved: ${result.outcome}.',
      );
    }

    if (result.serverRevision != 1) {
      throw StateError('Dependency receipt must establish revision 1.');
    }

    await mutationRunner.run<void>((context) async {
      final dependencies = context.artistDependencyJournalRepository;
      final baselines = context.cloudRevisionBaselineRepository;

      if (dependencies == null || baselines == null) {
        throw StateError('Dependency finalization repositories unavailable.');
      }

      final stored = await dependencies.findUnresolved(
        userId: entry.userId,
        artistId: entry.artistId,
      );

      if (stored == null || !stored.sameSnapshot(entry)) {
        throw StateError('Dependency journal changed during cloud replay.');
      }

      final current = await baselines.getRevision(
        userId: entry.userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.artistId,
      );

      if (current != null && current != 1) {
        throw StateError('Artist baseline changed during dependency recovery.');
      }

      await baselines.saveObservedRevision(
        userId: entry.userId,
        entityType: CloudDataEntity.artist,
        entityId: entry.artistId,
        serverRevision: 1,
      );

      final removed = await dependencies.removeVerified(entry);
      if (removed != 1) {
        throw StateError('Verified dependency journal removal failed.');
      }

      // Deliberately no localSyncRepository.markProcessed().
      // Explicit artist edits remain in their original outbox.
    });
  }
}
