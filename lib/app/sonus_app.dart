import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../features/account/domain/repositories/account_repository.dart';
import '../features/account/presentation/scopes/account_scope.dart';
import '../features/library/presentation/scopes/library_query_scope.dart';
import '../features/player/presentation/scopes/playback_scope.dart';
import '../features/shell/presentation/pages/app_shell_page.dart';

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
    return PlaybackScope(
      engineFactory: playbackEngineFactory,
      child: LibraryQueryScope(
        database: libraryDatabase,
        child: AccountScope(
          repository: accountRepository,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Sonus',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
            home: const AppShellPage(),
          ),
        ),
      ),
    );
  }
}
