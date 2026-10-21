import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/account_sync_ownership_attachment_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../account/data/repositories/sqlite_local_account_binding_repository.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/metadata_field_state_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_metadata_field_state_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../application/controllers/sync_controller.dart';
import '../../application/services/automatic_sync_coordinator.dart';
import '../../application/services/inbound_sync_processor.dart';
import '../../application/services/inbound_sync_reconciler.dart';
import '../../application/services/outbound_sync_processor.dart';
import '../../application/services/artist_receipt_cutover_policy.dart';
import '../../application/services/artist_dependency_recovery_service.dart';
import '../../application/services/artist_write_recovery_service.dart';
import '../../application/services/outbound_artist_receipt_pipeline.dart';
import '../../data/gateways/artist_dependency_receipt_replay_gateway.dart';
import '../../data/gateways/artist_journal_replay_gateway.dart';
import '../../application/services/outbound_artist_write_committer.dart';
import '../../application/services/outbound_artist_write_coordinator.dart';
import '../../application/services/outbound_artist_dependency_ensurer.dart';
import '../../application/services/sync_network_policy_service.dart';
import '../../application/services/sync_run_guard.dart';
import '../../application/services/sync_service.dart';
import '../../data/daos/local_sync_dao.dart';
import '../../data/daos/cloud_revision_baseline_dao.dart';
import '../../data/gateways/supabase_cloud_sync_gateway.dart';
import '../../data/gateways/supabase_artist_create_gateway.dart';
import '../../data/gateways/supabase_artist_record_conditional_write_gateway.dart';
import '../../data/gateways/supabase_cloud_sync_reader.dart';
import '../../data/repositories/sqlite_local_sync_repository.dart';
import '../../data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import '../../data/repositories/sync_mutation_transaction_runner.dart';
import '../../data/services/supabase_cloud_artwork_storage.dart';
import '../widgets/automatic_sync_lifecycle_bridge.dart';

class SyncScope extends StatefulWidget {
  const SyncScope({super.key, required this.child, this.database});

  final Widget child;
  final AppDatabase? database;

  @override
  State<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends State<SyncScope> {
  AppDatabase? _database;
  SyncController? _syncController;
  AutomaticSyncCoordinator? _automaticSyncCoordinator;

  bool _initializationStarted = false;
  bool _ownsDatabase = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final accountController = context.read<AccountController?>();

    if (accountController == null || _initializationStarted) {
      return;
    }

    _initializationStarted = true;
    unawaited(_initialize(context.read<SyncRunGuard?>()));
  }

  Future<void> _initialize(SyncRunGuard? runGuard) async {
    final database = widget.database ?? AppDatabase();
    final ownsDatabase = widget.database == null;

    final executor = await database.database;

    final localSyncRepository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(executor),
      generateId: EntityId.syncOutbox,
      now: DateTime.now,
    );

    final client = Supabase.instance.client;

    // All local completion operations use the same database and
    // transactional repository contracts.
    final mutationRunner = SyncMutationTransactionRunner(appDatabase: database);

    final revisionBaselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(executor),
    );

    final artistCreateGateway = SupabaseArtistCreateGateway(client: client);

    final artistUpdateGateway = SupabaseArtistRecordConditionalWriteGateway(
      client: client,
    );

    final artistWriteCoordinator = OutboundArtistWriteCoordinator(
      baselineRepository: revisionBaselines,
      createArtist: artistCreateGateway.createArtist,
      updateArtist: artistUpdateGateway.updateArtist,
      committer: OutboundArtistWriteCommitter(mutationRunner: mutationRunner),
    );

    final artistDependencyEnsurer = OutboundArtistDependencyEnsurer(
      baselineRepository: revisionBaselines,
      createArtist: artistCreateGateway.createArtist,
      mutationRunner: mutationRunner,
    );

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
      artworkAssetRepository: SqliteArtworkAssetRepository(
        ArtworkAssetDao(executor),
      ),
      cloudArtworkStorage: SupabaseCloudArtworkStorage(client: client),
      cloudSyncGateway: SupabaseCloudSyncGateway(client: client),
      cloudRevisionBaselineRepository: revisionBaselines,
      pushArtistMutation:
          receiptPipeline?.pushUpsert ?? artistWriteCoordinator.push,
      pushArtistDeletion: receiptPipeline?.pushDelete,
      ensureArtistDependency:
          receiptPipeline?.guardedDependency ?? artistDependencyEnsurer.ensure,
      recoverArtistWrites: receiptPipeline?.recover,
    );

    final inboundReconciler = InboundSyncReconciler(
      reader: SupabaseCloudSyncReader(client: client),
      localSyncRepository: localSyncRepository,
      mutationRunner: mutationRunner,
    );

    final inboundProcessor = InboundSyncProcessor(
      reconciler: inboundReconciler,
      replayWindow: const Duration(minutes: 2),
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
    );

    final syncController = SyncController(service: service);

    final automaticSyncCoordinator = AutomaticSyncCoordinator(
      syncController: syncController,
      networkPolicy: SyncNetworkPolicyService(),
    );

    if (!mounted) {
      syncController.dispose();
      automaticSyncCoordinator.dispose();

      if (ownsDatabase) {
        await database.close();
      }

      return;
    }

    setState(() {
      _database = database;
      _ownsDatabase = ownsDatabase;
      _syncController = syncController;
      _automaticSyncCoordinator = automaticSyncCoordinator;
    });
  }

  @override
  void dispose() {
    _automaticSyncCoordinator?.dispose();
    _syncController?.dispose();

    final database = _database;

    if (_ownsDatabase && database != null) {
      unawaited(database.close());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncController = _syncController;
    final automaticSyncCoordinator = _automaticSyncCoordinator;

    if (syncController == null || automaticSyncCoordinator == null) {
      return widget.child;
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncController>.value(value: syncController),
        ChangeNotifierProvider<AutomaticSyncCoordinator>.value(
          value: automaticSyncCoordinator,
        ),
      ],
      child: AutomaticSyncLifecycleBridge(child: widget.child),
    );
  }
}
