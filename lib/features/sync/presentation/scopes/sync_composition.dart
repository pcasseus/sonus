import '../../application/services/cloud_deletion_readiness.dart';
import '../../../library/data/repositories/sqlite_album_edition_disc_label_repository.dart';
import '../../../library/data/repositories/sqlite_library_deletion_ledger.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/events/library_change_signal.dart';

import '../../../../app/account_sync_ownership_attachment_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../account/data/repositories/sqlite_local_account_binding_repository.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/daos/album_edition_track_dao.dart';
import '../../../library/data/daos/song_artist_credit_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_track_repository.dart';
import '../../../library/data/repositories/sqlite_song_artist_credit_repository.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/metadata_field_state_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_metadata_field_state_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../application/services/inbound_sync_processor.dart';
import '../../application/services/inbound_sync_reconciler.dart';
import '../../application/services/outbound_sync_processor.dart';
import '../../application/services/artist_receipt_cutover_policy.dart';
import '../../application/services/artist_dependency_recovery_service.dart';
import '../../application/services/artist_write_recovery_service.dart';
import '../../application/services/outbound_artist_receipt_pipeline.dart';
import '../../data/gateways/artist_dependency_receipt_replay_gateway.dart';
import '../../data/gateways/artist_journal_replay_gateway.dart';
import '../../application/services/outbound_acknowledgement.dart';
import '../../application/services/sync_run_guard.dart';
import '../../application/services/sync_service.dart';
import '../../data/daos/local_sync_dao.dart';
import '../../data/daos/cloud_revision_baseline_dao.dart';
import '../../data/daos/outbound_conflict_dao.dart';
import '../../data/gateways/supabase_cloud_sync_gateway.dart';
import '../../data/gateways/supabase_cloud_sync_reader.dart';
import '../../data/repositories/sqlite_local_sync_repository.dart';
import '../../data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import '../../data/repositories/sqlite_outbound_conflict_repository.dart';
import '../../data/repositories/sync_mutation_transaction_runner.dart';
import '../../data/services/supabase_cloud_artwork_storage.dart';
import '../../data/services/supabase_sync_failure_classifier.dart';
import '../../application/services/cloud_archive_sync_service.dart';
import '../../application/services/cloud_library_first_link_guard.dart';
import '../../data/gateways/supabase_cloud_archive_gateway.dart';
import '../../data/services/sqlite_cloud_archive_store.dart';
import '../../data/services/supabase_cloud_library_probe.dart';
import '../../data/services/sync_status_store.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artwork_recovery_composition.dart';
import 'legacy_artist_sync_composition.dart';

/// The app's sync stack for one database and one Supabase client: the
/// library push and pull, the archive, first-link protection and the
/// permanent-deletion capability probe. [SyncScope] builds it for the app;
/// the isolated staging harness builds the same thing against a local
/// server, so what is tested there is what ships.
class SyncComposition {
  SyncComposition._({
    required this.service,
    required this.deletionReadiness,
    required this.consent,
    required this.statusStore,
  });

  final SyncService service;
  final CloudDeletionReadiness deletionReadiness;
  final CloudLibraryConsentStore consent;
  final SyncStatusStore statusStore;

  static Future<SyncComposition> build({
    required AppDatabase database,
    required SupabaseClient client,
    SyncRunGuard? runGuard,
    CloudLibraryConsentStore? consentStore,
    SyncStatusStore? syncStatusStore,
    LibraryChangeSignal? changes,
  }) async {
    final executor = await database.database;

    final localSyncRepository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(executor),
      generateId: EntityId.syncOutbox,
      now: DateTime.now,
    );

    // All local completion operations use the same database and
    // transactional repository contracts.
    final mutationRunner = SyncMutationTransactionRunner(appDatabase: database);

    final revisionBaselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(executor),
    );

    // The active artist route. Both services verify a rejected creation
    // against the fetched cloud artist before adopting it.
    final legacyArtistSync = LegacyArtistSyncComposition(
      client: client,
      baselineRepository: revisionBaselines,
      mutationRunner: mutationRunner,
    );

    final artistWriteCoordinator = legacyArtistSync.writeCoordinator;
    final artistDependencyEnsurer = legacyArtistSync.dependencyEnsurer;

    // SN-41 receipt path is intentionally disabled pending:
    // - local mutation/dependency race resolution;
    // - live Supabase SQL verification;
    // - explicit production cutover approval.
    //
    // The existing artist coordinator remains the active route.
    // Constructed only for the approved receipt-aware branch.
    // The active legacy sync route remains unchanged while disabled.
    final dependencyRecovery = ArtistReceiptCutoverPolicy.enabled
        ? ArtistDependencyRecoveryService(
            mutationRunner: mutationRunner,
            generateRequestId: EntityId.syncOutbox,
            now: DateTime.now,
            replayReceipt: ArtistDependencyReceiptReplayGateway(
              artistGateway: ArtistJournalReplayGateway(
                invokeRpc: (name, parameters) async =>
                    client.rpc(name, params: parameters),
              ),
            ).replay,
          )
        : null;

    final receiptPipeline = ArtistReceiptCutoverPolicy.enabled
        ? OutboundArtistReceiptPipeline(
            recovery: ArtistWriteRecoveryService(
              mutationRunner: mutationRunner,
              now: DateTime.now,
              replayGateway: ArtistJournalReplayGateway(
                invokeRpc: (name, parameters) async =>
                    client.rpc(name, params: parameters),
              ),
            ),
            mutationRunner: mutationRunner,
            dependencyRecovery: dependencyRecovery,
            ensureDependency: dependencyRecovery!.ensure,
          )
        : null;

    final outboundProcessor = OutboundSyncProcessor(
      localSyncRepository: localSyncRepository,
      artistRepository: SqliteArtistRepository(ArtistDao(executor)),
      albumRepository: SqliteAlbumRepository(AlbumDao(executor)),
      albumEditionRepository: SqliteAlbumEditionRepository(
        AlbumEditionDao(executor),
      ),
      songRepository: SqliteSongRepository(SongDao(executor)),
      metadataFieldStateRepository: SqliteMetadataFieldStateRepository(
        MetadataFieldStateDao(executor),
      ),
      discLabelRepository: SqliteAlbumEditionDiscLabelRepository(executor),
      artworkAssetRepository: SqliteArtworkAssetRepository(
        ArtworkAssetDao(executor),
      ),
      cloudArtworkStorage: SupabaseCloudArtworkStorage(client: client),
      cloudSyncGateway: SupabaseCloudSyncGateway(client: client),
      // A cloud without this version's tables, columns or functions ends
      // the push at once, so the run pauses instead of retrying (DQA-01).
      isPermanentFailure: (error) =>
          classifySupabaseSyncFailure(error).isPermanent,
      isPermanentlyDeleted: (entityType, entityId) async {
        final ledgerEntity = switch (entityType) {
          CloudDataEntity.artist => DeletionLedgerEntity.artist,
          CloudDataEntity.album => DeletionLedgerEntity.album,
          CloudDataEntity.albumEdition => DeletionLedgerEntity.albumEdition,
          CloudDataEntity.song => DeletionLedgerEntity.song,
          CloudDataEntity.artworkAsset => null,
        };
        return ledgerEntity != null &&
            await SqliteLibraryDeletionLedger(
              executor,
            ).contains(ledgerEntity, entityId);
      },
      cloudRevisionBaselineRepository: revisionBaselines,
      pushArtistMutation:
          receiptPipeline?.pushUpsert ?? artistWriteCoordinator.push,
      pushArtistDeletion: receiptPipeline?.pushDelete,
      ensureArtistDependency:
          receiptPipeline?.guardedDependency ?? artistDependencyEnsurer.ensure,
      recoverArtistWrites: receiptPipeline?.recover,
      outboundConflictRepository: SqliteOutboundConflictRepository(
        dao: OutboundConflictDao(executor),
      ),
      acknowledgeEntry: TransactionalOutboundAcknowledgement(
        mutationRunner: mutationRunner,
      ).acknowledge,
      albumEditionTrackRepository: SqliteAlbumEditionTrackRepository(
        AlbumEditionTrackDao(executor),
      ),
      songArtistCreditRepository: SqliteSongArtistCreditRepository(
        SongArtistCreditDao(executor),
      ),
    );

    final inboundReconciler = InboundSyncReconciler(
      reader: SupabaseCloudSyncReader(client: client),
      localSyncRepository: localSyncRepository,
      mutationRunner: mutationRunner,
      // Deferred cloud-only artwork is downloaded during replay.
      recoverArtwork: createCloudArtworkRecovery(client: client).recover,
    );

    final inboundProcessor = InboundSyncProcessor(
      reconciler: inboundReconciler,
      replayWindow: const Duration(minutes: 2),
    );

    final consent = consentStore ?? SharedPreferencesCloudLibraryConsentStore();
    final archiveGateway = SupabaseCloudArchiveGateway(client: client);
    final deletionReadiness = CloudDeletionReadiness(
      archiveGateway.supportsPermanentDeletion,
    );
    final archive = CloudArchiveSyncService(
      gateway: archiveGateway,
      store: SqliteCloudArchiveStore(appDatabase: database, changes: changes),
      queueArtworkUpload: ({required userId, required artworkId}) =>
          localSyncRepository.recordUpsert(
            userId: userId,
            entityType: CloudDataEntity.artworkAsset,
            entityId: artworkId,
          ),
    );
    // Shared with the controller, which records each completed sync: a
    // device counts as linked to an account only once it has synced with
    // it, never merely because someone signed in.
    final statusStore = syncStatusStore ?? SyncStatusStore();
    final firstLink = CloudLibraryFirstLinkGuard(
      syncedBefore: (userId) async =>
          await statusStore.getLastSuccessfulSync(userId) != null,
      probe: SupabaseCloudLibraryProbe(client: client),
      consent: consent,
    );

    final service = SyncService(
      attachAccount: AccountSyncOwnershipAttachmentService(
        appDatabase: database,
      ).attachUnownedToUser,
      accountBindingRepository: SqliteLocalAccountBindingRepository(
        appDatabase: database,
      ),
      localSyncRepository: localSyncRepository,
      localSyncOwnershipRepository: localSyncRepository,
      outboundSyncProcessor: outboundProcessor,
      inboundSyncProcessor: inboundProcessor,
      // Recovery pauses every run, automatic or manual, while restoring.
      runGuard: runGuard,
      firstLinkGuard: firstLink.check,
      syncArchive: (userId) => archive.synchronize(userId),
    );

    return SyncComposition._(
      service: service,
      deletionReadiness: deletionReadiness,
      consent: consent,
      statusStore: statusStore,
    );
  }
}
