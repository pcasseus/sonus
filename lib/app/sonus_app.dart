import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/database/app_database.dart';
import '../features/account/domain/repositories/account_repository.dart';
import '../features/account/presentation/scopes/account_scope.dart';
import '../features/analytics/presentation/scopes/monthly_listening_insights_scope.dart';
import '../features/analytics/presentation/scopes/year_in_sonus_scope.dart';
import '../features/charts/presentation/scopes/charts_scope.dart';
import '../features/home/presentation/scopes/home_scope.dart';
import '../features/import/presentation/scopes/import_scope.dart';
import '../features/library/presentation/scopes/library_query_scope.dart';
import '../features/player/presentation/scopes/playback_scope.dart';
import '../features/playlists/presentation/scopes/playlists_scope.dart';
import '../features/recovery/application/services/recovery_service.dart';
import '../features/recovery/application/services/recovery_sync_gate.dart';
import '../features/recovery/presentation/scopes/recovery_scope.dart';
import '../features/shell/presentation/pages/app_shell_page.dart';
import '../features/sync/application/services/sync_run_guard.dart';
import '../features/sync/presentation/scopes/sync_scope.dart';
import 'account_analytics_bridge.dart';
import 'account_sync_ownership_bridge.dart';
import 'app_restart_scope.dart';

class SonusApp extends StatefulWidget {
  const SonusApp({
    super.key,
    this.playbackEngineFactory,
    this.libraryDatabase,
    this.accountRepository,
    this.recoverySyncGate,
    this.recoveryService,
  });

  final PlaybackEngineFactory? playbackEngineFactory;
  final AppDatabase? libraryDatabase;
  final AccountRepository? accountRepository;

  /// Shared by sync and backup recovery; defaults to the app-wide gate.
  final RecoverySyncGate? recoverySyncGate;

  /// Overrides the platform recovery service (tests).
  final RecoveryService? recoveryService;

  @override
  State<SonusApp> createState() => _SonusAppState();
}

class _SonusAppState extends State<SonusApp> {
  // One database for the whole app. Scopes below receive it rather than
  // opening and closing their own handles, so a reload after a restore
  // rebuilds them without closing the database underneath them.
  late final AppDatabase _database = widget.libraryDatabase ?? AppDatabase();
  late final bool _ownsDatabase = widget.libraryDatabase == null;

  @override
  void dispose() {
    if (_ownsDatabase) {
      unawaited(_database.close());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gate = widget.recoverySyncGate ?? RecoverySyncGate.application;

    return MultiProvider(
      providers: [
        Provider<RecoverySyncGate?>.value(value: gate),
        Provider<SyncRunGuard?>.value(value: gate),
      ],
      child: AppRestartScope(
        child: LibraryQueryScope(
          database: _database,
          child: PlaylistsScope(
            child: PlaybackScope(
              engineFactory: widget.playbackEngineFactory,
              child: AccountScope(
                repository: widget.accountRepository,
                child: SyncScope(
                  database: _database,
                  // Unchanged: only an injected database activates it.
                  child: AccountSyncOwnershipBridge(
                    database: widget.libraryDatabase,
                    child: AccountAnalyticsBridge(
                      child: MonthlyListeningInsightsScope(
                        child: YearInSonusScope(
                          child: HomeScope(
                            child: ChartsScope(
                              child: ImportScope(
                                child: RecoveryScope(
                                  service: widget.recoveryService,
                                  child: MaterialApp(
                                    debugShowCheckedModeBanner: false,
                                    title: 'Sonus',
                                    theme: ThemeData(
                                      colorScheme: ColorScheme.fromSeed(
                                        seedColor: Colors.deepPurple,
                                      ),
                                    ),
                                    home: const AppShellPage(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
