import 'package:flutter/material.dart';

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
import '../features/shell/presentation/pages/app_shell_page.dart';
import 'account_analytics_bridge.dart';
import 'account_sync_ownership_bridge.dart';

class SonusApp extends StatelessWidget {
  const SonusApp({
    super.key,
    this.playbackEngineFactory,
    this.libraryDatabase,
    this.accountRepository,
  });

  final PlaybackEngineFactory? playbackEngineFactory;
  final AppDatabase? libraryDatabase;
  final AccountRepository? accountRepository;

  @override
  Widget build(BuildContext context) {
    return LibraryQueryScope(
      database: libraryDatabase,
      child: PlaylistsScope(
        child: PlaybackScope(
          engineFactory: playbackEngineFactory,
          child: AccountScope(
            repository: accountRepository,
            child: AccountSyncOwnershipBridge(
              database: libraryDatabase,
              child: AccountAnalyticsBridge(
                child: MonthlyListeningInsightsScope(
                  child: YearInSonusScope(
                    child: HomeScope(
                      child: ChartsScope(
                        child: ImportScope(
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
    );
  }
}
