import '../../application/services/cloud_deletion_readiness.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../application/controllers/sync_controller.dart';
import '../../application/services/automatic_sync_coordinator.dart';
import '../../application/services/sync_network_policy_service.dart';
import '../../application/services/sync_run_guard.dart';
import '../../data/services/supabase_sync_failure_classifier.dart';
import '../widgets/automatic_sync_lifecycle_bridge.dart';
import 'sync_composition.dart';

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
  CloudDeletionReadiness? _deletionReadiness;
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

    final composition = await SyncComposition.build(
      database: database,
      client: Supabase.instance.client,
      runGuard: runGuard,
    );
    _deletionReadiness = composition.deletionReadiness;
    final consent = composition.consent;
    final statusStore = composition.statusStore;
    final service = composition.service;

    final syncController = SyncController(
      service: service,
      classifyFailure: classifySupabaseSyncFailure,
      describeFailure: describeSupabaseSyncFailure,
      grantCloudLibrary: consent.grant,
      statusStore: statusStore,
    );

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
        Provider<CloudDeletionReadiness?>.value(value: _deletionReadiness),
      ],
      child: AutomaticSyncLifecycleBridge(child: widget.child),
    );
  }
}
