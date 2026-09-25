import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../artwork/data/daos/artwork_asset_dao.dart';
import '../../../artwork/data/repositories/sqlite_artwork_asset_repository.dart';
import '../../../artwork/data/services/file_system_artwork_managed_storage.dart';
import '../../../artwork/presentation/services/file_picker_artwork_file_picker.dart';
import '../../../sync/data/repositories/sync_mutation_transaction_runner.dart';
import '../../../search/application/repositories/library_search_repository.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../data/daos/album_edition_dao.dart';
import '../../data/daos/artist_dao.dart';
import '../../data/daos/library_query_dao.dart';
import '../../data/daos/song_dao.dart';
import '../../data/repositories/sqlite_album_edition_repository.dart';
import '../../data/repositories/sqlite_artist_repository.dart';
import '../../data/repositories/sqlite_library_query_repository.dart';
import '../../data/repositories/sqlite_song_repository.dart';

class LibraryQueryScope extends StatefulWidget {
  const LibraryQueryScope({super.key, required this.child, this.database});

  final Widget child;
  final AppDatabase? database;

  @override
  State<LibraryQueryScope> createState() => _LibraryQueryScopeState();
}

class _LibraryQueryScopeState extends State<LibraryQueryScope> {
  late final AppDatabase _database;
  late final bool _ownsDatabase;

  LibraryQueryRepository? _repository;
  LibrarySearchRepository? _searchRepository;
  ArtworkAssignmentService? _artworkAssignmentService;
  AlbumProfileEditingService? _albumProfileEditingService;
  ArtistCreationService? _artistCreationService;
  ArtistProfileEditingService? _artistProfileEditingService;
  TrackProfileEditingService? _trackProfileEditingService;

  @override
  void initState() {
    super.initState();

    _ownsDatabase = widget.database == null;
    _database = widget.database ?? AppDatabase();

    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final database = await _database.database;

    final libraryQueryRepository = SqliteLibraryQueryRepository(
      LibraryQueryDao(database),
    );

    final artworkAssignmentService = ArtworkAssignmentService(
      artworkAssetRepository: SqliteArtworkAssetRepository(
        ArtworkAssetDao(database),
      ),
      artistRepository: SqliteArtistRepository(ArtistDao(database)),
      albumEditionRepository: SqliteAlbumEditionRepository(
        AlbumEditionDao(database),
      ),
      songRepository: SqliteSongRepository(SongDao(database)),
      artworkManagedStorage: FileSystemArtworkManagedStorage(),
    );

    final albumProfileEditingService = AlbumProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: _database),
    );

    final artistCreationService = ArtistCreationService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: _database),
    );

    final artistProfileEditingService = ArtistProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: _database),
    );

    final trackProfileEditingService = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: _database),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _repository = libraryQueryRepository;
      _searchRepository = libraryQueryRepository;
      _artworkAssignmentService = artworkAssignmentService;
      _albumProfileEditingService = albumProfileEditingService;
      _artistCreationService = artistCreationService;
      _artistProfileEditingService = artistProfileEditingService;
      _trackProfileEditingService = trackProfileEditingService;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: _database),
        Provider<LibraryQueryRepository?>.value(value: _repository),
        Provider<LibrarySearchRepository?>.value(value: _searchRepository),
        Provider<ArtworkAssignmentService?>.value(
          value: _artworkAssignmentService,
        ),
        Provider<AlbumProfileEditingService?>.value(
          value: _albumProfileEditingService,
        ),
        Provider<ArtistCreationService?>.value(value: _artistCreationService),
        Provider<ArtistProfileEditingService?>.value(
          value: _artistProfileEditingService,
        ),
        Provider<TrackProfileEditingService?>.value(
          value: _trackProfileEditingService,
        ),
        Provider<ArtworkFilePicker>.value(
          value: const FilePickerArtworkFilePicker(),
        ),
      ],
      child: widget.child,
    );
  }

  @override
  void dispose() {
    if (_ownsDatabase) {
      unawaited(_database.close());
    }

    super.dispose();
  }
}
