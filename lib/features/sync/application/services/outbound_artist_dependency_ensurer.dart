import '../repositories/cloud_revision_baseline_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artist_create_verifier.dart';
import 'cloud_conditional_write_result.dart';
import 'outbound_artist_write_coordinator.dart';
import 'sync_mutation_runner.dart';

/// Establishes that a referenced artist exists in the cloud without
/// overwriting an existing artist or acknowledging local mutations.
class OutboundArtistDependencyEnsurer {
  const OutboundArtistDependencyEnsurer({
    required this.baselineRepository,
    required this.createArtist,
    required this.mutationRunner,
    required this.fetchCurrentArtist,
  });

  final CloudRevisionBaselineRepository baselineRepository;
  final CreateCloudArtist createArtist;
  final SyncMutationRunner mutationRunner;
  final FetchCurrentCloudArtist fetchCurrentArtist;

  Future<void> ensure({
    required String userId,
    required CloudArtistRecord artist,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty ||
        artist.userId != owner ||
        artist.id.trim().isEmpty ||
        artist.isDeleted) {
      throw StateError('Invalid artist dependency or account ownership.');
    }

    final existingRevision = await baselineRepository.getRevision(
      userId: owner,
      entityType: CloudDataEntity.artist,
      entityId: artist.id,
    );

    if (existingRevision != null) {
      if (existingRevision < 1) {
        throw StateError('Invalid artist dependency baseline.');
      }

      return;
    }

    // The RPC must be insert-only. A conflict is not proof that
    // the existing cloud record matches local data.
    final result = await createArtist(artist: artist);

    if (result.outcome == CloudConditionalWriteOutcome.conflict) {
      // Only a fetched, verified copy of this exact artist is adopted,
      // for example our own creation whose response was lost.
      final adoptedRevision = await CloudArtistCreateVerifier(
        fetchCurrentArtist: fetchCurrentArtist,
      ).adoptableRevision(userId: owner, artist: artist);

      if (adoptedRevision != null) {
        await _saveBaseline(owner, artist.id, adoptedRevision);
        return;
      }
    }

    if (result.outcome != CloudConditionalWriteOutcome.applied) {
      throw OutboundArtistWriteConflict(
        artistId: artist.id,
        outcome: result.outcome,
        expectedServerRevision: null,
        observedServerRevision: result.serverRevision,
      );
    }

    if (result.serverRevision != 1) {
      throw StateError('New cloud artist must start at revision 1.');
    }

    await _saveBaseline(owner, artist.id, 1);
  }

  Future<void> _saveBaseline(String owner, String artistId, int revision) {
    return mutationRunner.run<void>((context) async {
      final repository = context.cloudRevisionBaselineRepository;

      if (repository == null) {
        throw StateError('Missing transactional cloud baseline repository.');
      }

      // Deliberately do not acknowledge or remove any outbox entry.
      // A newer local artist mutation may still need to be uploaded.
      await repository.saveObservedRevision(
        userId: owner,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
        serverRevision: revision,
      );
    });
  }
}
