import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/identity/entity_id.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../account/data/repositories/sqlite_local_account_binding_repository.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../library/data/daos/album_dao.dart';
import '../../../library/data/daos/album_edition_dao.dart';
import '../../../library/data/daos/artist_dao.dart';
import '../../../library/data/daos/song_dao.dart';
import '../../../library/data/repositories/sqlite_album_edition_repository.dart';
import '../../../library/data/repositories/sqlite_album_repository.dart';
import '../../../library/data/repositories/sqlite_artist_repository.dart';
import '../../../library/data/repositories/sqlite_song_repository.dart';
import '../../application/controllers/sync_controller.dart';
import '../../application/services/automatic_sync_coordinator.dart';
import '../../application/services/inbound_sync_processor.dart';
import '../../application/services/inbound_sync_reconciler.dart';
import '../../application/services/outbound_sync_processor.dart';
import '../../application/services/sync_network_policy_service.dart';
import '../../application/services/sync_service.dart';
import '../../data/daos/local_sync_dao.dart';
import '../../data/gateways/supabase_cloud_sync_gateway.dart';
import '../../data/gateways/supabase_cloud_sync_reader.dart';
import '../../data/repositories/sqlite_local_sync_repository.dart';
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
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final database = widget.database ?? AppDatabase();
    final ownsDatabase = widget.database == null;

    final executor = await database.database;

    final localSyncRepository = SqliteLocalSyncRepository(
      dao: LocalSyncDao(executor),
      generateId: EntityId.syncOutbox,
      now: DateTime.now,
    );

    final client = Supabase.instance.client;

    final outboundProcessor = OutboundSyncProcessor(
      localSyncRepository: localSyncRepository,
      artistRepository: SqliteArtistRepository(ArtistDao(executor)),
      albumRepository: SqliteAlbumRepository(AlbumDao(executor)),
      albumEditionRepository: SqliteAlbumEditionRepository(
        AlbumEditionDao(executor),
      ),
      songRepository: SqliteSongRepository(SongDao(executor)),
      artworkAssetRepository: SqliteArtworkAssetRepository(
        ArtworkAssetDao(executor),
      ),
      cloudArtworkStorage: SupabaseCloudArtworkStorage(client: client),
      cloudSyncGateway: SupabaseCloudSyncGateway(client: client),
    );

    final inboundReconciler = InboundSyncReconciler(
      reader: SupabaseCloudSyncReader(client: client),
      localSyncRepository: localSyncRepository,
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );

    final inboundProcessor = InboundSyncProcessor(
      reconciler: inboundReconciler,
      replayWindow: const Duration(minutes: 2),
    );

    final service = SyncService(
      accountBindingRepository: SqliteLocalAccountBindingRepository(
        appDatabase: database,
      ),
      localSyncRepository: localSyncRepository,
      localSyncOwnershipRepository: localSyncRepository,
      outboundSyncProcessor: outboundProcessor,
      inboundSyncProcessor: inboundProcessor,
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
