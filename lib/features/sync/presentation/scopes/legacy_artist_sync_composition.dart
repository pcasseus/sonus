import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/repositories/cloud_revision_baseline_repository.dart';
import '../../application/services/cloud_sync_reader.dart';
import '../../application/services/outbound_artist_dependency_ensurer.dart';
import '../../application/services/outbound_artist_write_committer.dart';
import '../../application/services/outbound_artist_write_coordinator.dart';
import '../../application/services/sync_mutation_runner.dart';
import '../../data/gateways/supabase_artist_create_gateway.dart';
import '../../data/gateways/supabase_artist_record_conditional_write_gateway.dart';
import '../../data/gateways/supabase_cloud_sync_gateway.dart';
import '../../domain/models/sync_data_contract.dart';

/// Production composition of the active legacy (non-receipt) artist
/// route used by SyncScope.
///
/// Both services read the current cloud artist through
/// [SupabaseCloudSyncGateway] to verify a rejected creation before
/// adopting it. Kept separate from SyncScope so the exact production
/// wiring can be tested without a live Supabase project.
class LegacyArtistSyncComposition {
  factory LegacyArtistSyncComposition({
    required SupabaseClient client,
    required CloudRevisionBaselineRepository baselineRepository,
    required SyncMutationRunner mutationRunner,
  }) {
    final createGateway = SupabaseArtistCreateGateway(client: client);
    final updateGateway = SupabaseArtistRecordConditionalWriteGateway(
      client: client,
    );
    final cloudSyncGateway = SupabaseCloudSyncGateway(client: client);

    Future<CloudSyncItem?> fetchCurrentArtist({
      required String userId,
      required String artistId,
    }) {
      return cloudSyncGateway.fetchCurrent(
        userId: userId,
        entityType: CloudDataEntity.artist,
        entityId: artistId,
      );
    }

    return LegacyArtistSyncComposition._(
      writeCoordinator: OutboundArtistWriteCoordinator(
        baselineRepository: baselineRepository,
        createArtist: createGateway.createArtist,
        updateArtist: updateGateway.updateArtist,
        committer: OutboundArtistWriteCommitter(mutationRunner: mutationRunner),
        fetchCurrentArtist: fetchCurrentArtist,
      ),
      dependencyEnsurer: OutboundArtistDependencyEnsurer(
        baselineRepository: baselineRepository,
        createArtist: createGateway.createArtist,
        mutationRunner: mutationRunner,
        fetchCurrentArtist: fetchCurrentArtist,
      ),
    );
  }

  const LegacyArtistSyncComposition._({
    required this.writeCoordinator,
    required this.dependencyEnsurer,
  });

  final OutboundArtistWriteCoordinator writeCoordinator;
  final OutboundArtistDependencyEnsurer dependencyEnsurer;
}
