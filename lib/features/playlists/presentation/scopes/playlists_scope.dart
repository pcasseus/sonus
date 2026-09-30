import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../sync/data/repositories/sync_mutation_transaction_runner.dart';
import '../../application/services/playlist_service.dart';
import '../../data/daos/playlist_dao.dart';
import '../../data/repositories/sqlite_playlist_repository.dart';

class PlaylistsScope extends StatefulWidget {
  const PlaylistsScope({super.key, required this.child});

  final Widget child;

  @override
  State<PlaylistsScope> createState() => _PlaylistsScopeState();
}

class _PlaylistsScopeState extends State<PlaylistsScope> {
  AppDatabase? _database;
  LibraryQueryRepository? _library;
  PlaylistService? _service;

  int _initializationVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();
    final library = context.watch<LibraryQueryRepository?>();

    if (identical(database, _database) && identical(library, _library)) {
      return;
    }

    _database = database;
    _library = library;

    final version = ++_initializationVersion;

    setState(() {
      _service = null;
    });

    if (library == null) {
      return;
    }

    unawaited(
      _initialize(database: database, library: library, version: version),
    );
  }

  Future<void> _initialize({
    required AppDatabase database,
    required LibraryQueryRepository library,
    required int version,
  }) async {
    final sqlite = await database.database;

    final service = PlaylistService(
      repository: SqlitePlaylistRepository(PlaylistDao(sqlite)),
      library: library,
      mutationRunner: SyncMutationTransactionRunner(appDatabase: database),
    );

    if (!mounted || version != _initializationVersion) {
      return;
    }

    setState(() {
      _service = service;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Provider<PlaylistService?>.value(
      value: _service,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _initializationVersion++;
    super.dispose();
  }
}
