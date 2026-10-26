import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../playlists/application/services/playlist_service.dart';
import '../../application/controllers/playback_coordinator.dart';
import '../../application/controllers/playback_preferences_controller.dart';
import '../../application/controllers/playback_restoration_controller.dart';
import '../../application/services/media_session/media_browse_catalog.dart';
import '../../application/services/media_session/media_browse_library.dart';
import '../../application/services/media_session/sonus_audio_handler.dart';
import '../../data/daos/track_lyrics_dao.dart';
import '../../data/engines/just_audio_playback_engine.dart';
import '../../data/repositories/sqlite_track_lyrics_repository.dart';
import '../../data/services/playback_preferences_store.dart';
import '../../data/services/playback_session_store.dart';
import '../../data/services/recently_played_song_query.dart';
import '../../domain/repositories/track_lyrics_repository.dart';
import '../../domain/services/playback_engine.dart';
import '../controllers/lyrics_controller.dart';
import '../controllers/playback_state_controller.dart';

typedef PlaybackEngineFactory = PlaybackEngine Function();

class PlaybackScope extends StatefulWidget {
  const PlaybackScope({
    super.key,
    required this.child,
    this.engineFactory,
    this.preferencesStore,
    this.mediaSession,
    this.sessionStore,
  });

  final Widget child;
  final PlaybackEngineFactory? engineFactory;

  /// Overrides the device preference store (tests).
  final PlaybackPreferencesStore? preferencesStore;

  /// Android's media session, when available. It is bound to this
  /// scope's coordinator so notification, lock-screen and Bluetooth
  /// commands use the same playback authority as the app.
  final SonusAudioHandler? mediaSession;

  /// Overrides the device store for the restorable session (tests).
  final PlaybackSessionStore? sessionStore;

  @override
  State<PlaybackScope> createState() => _PlaybackScopeState();
}

class _PlaybackScopeState extends State<PlaybackScope>
    with WidgetsBindingObserver {
  late final PlaybackEngine _engine;
  late final PlaybackCoordinator _coordinator;
  late final PlaybackStateController _stateController;
  late final PlaybackPreferencesController _preferencesController;
  late final PlaybackRestorationController _restoration;
  late final Future<void> _preferencesLoaded;
  bool _restoreRequested = false;

  AppDatabase? _database;
  MediaBrowseCatalog? _catalog;
  LibraryQueryRepository? _catalogLibrary;
  PlaylistService? _catalogPlaylists;
  TrackLyricsRepository? _lyricsRepository;
  LyricsController? _lyricsController;
  int _initializationVersion = 0;

  @override
  void initState() {
    super.initState();

    _engine = widget.engineFactory?.call() ?? JustAudioPlaybackEngine();
    _coordinator = PlaybackCoordinator(engine: _engine);
    _stateController = PlaybackStateController(coordinator: _coordinator);
    _preferencesController = PlaybackPreferencesController(
      store: widget.preferencesStore ?? PlaybackPreferencesStore(),
      coordinator: _coordinator,
    );
    _preferencesLoaded = _preferencesController.load();
    _restoration = PlaybackRestorationController(
      store: widget.sessionStore ?? PlaybackSessionStore(),
      coordinator: _coordinator,
    );
    WidgetsBinding.instance.addObserver(this);
    widget.mediaSession?.attach(_coordinator);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The process may be killed without warning once Sonus is in the
    // background, so the position is saved as it leaves the screen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_restoration.saveNow());
    }
  }

  /// Restores the last queue, paused, once the library can be read and
  /// the saved shuffle and repeat modes have been applied.
  Future<void> _restoreSession(LibraryQueryRepository library) async {
    await _preferencesLoaded;
    if (!mounted) return;
    await _restoration.restore(library.getTracks);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final library = context.watch<LibraryQueryRepository?>();
    if (library != null && !_restoreRequested) {
      _restoreRequested = true;
      unawaited(_restoreSession(library));
    }

    final database = context.watch<AppDatabase>();

    _updateCatalog(
      library: library,
      playlists: context.watch<PlaylistService?>(),
      database: database,
    );

    if (identical(database, _database)) {
      return;
    }

    _database = database;

    final version = ++_initializationVersion;

    unawaited(_initializeLyrics(appDatabase: database, version: version));
  }

  /// Gives Android Auto the same library and playlists the app shows.
  void _updateCatalog({
    required LibraryQueryRepository? library,
    required PlaylistService? playlists,
    required AppDatabase database,
  }) {
    final session = widget.mediaSession;

    if (session == null ||
        library == null ||
        (identical(library, _catalogLibrary) &&
            identical(playlists, _catalogPlaylists))) {
      return;
    }

    final previous = _catalog;
    final catalog = MediaBrowseCatalog(
      library: RepositoryMediaBrowseLibrary(
        library: library,
        playlists: playlists,
        recentlyPlayedSongIds: (limit) async =>
            RecentlyPlayedSongQuery(await database.database).songIds(limit),
      ),
      artworkUri: session.carArtworkUri,
    );

    _catalog = catalog;
    _catalogLibrary = library;
    _catalogPlaylists = playlists;
    session.attachCatalog(catalog);

    if (previous != null) {
      session.detachCatalog(previous);
    }
  }

  Future<void> _initializeLyrics({
    required AppDatabase appDatabase,
    required int version,
  }) async {
    final database = await appDatabase.database;

    if (!mounted || version != _initializationVersion) {
      return;
    }

    final repository = SqliteTrackLyricsRepository(TrackLyricsDao(database));

    final controller = LyricsController(
      playbackCoordinator: _coordinator,
      repository: repository,
    );

    if (!mounted || version != _initializationVersion) {
      controller.dispose();
      return;
    }

    final previousController = _lyricsController;

    setState(() {
      _lyricsRepository = repository;
      _lyricsController = controller;
    });

    previousController?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PlaybackCoordinator>.value(value: _coordinator),
        ChangeNotifierProvider<PlaybackStateController>.value(
          value: _stateController,
        ),
        ChangeNotifierProvider<PlaybackPreferencesController>.value(
          value: _preferencesController,
        ),
        Provider<TrackLyricsRepository?>.value(value: _lyricsRepository),
        ChangeNotifierProvider<LyricsController?>.value(
          value: _lyricsController,
        ),
      ],
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _initializationVersion++;
    _lyricsController?.dispose();
    // Only unbinds if no newer scope has attached (restore reloads mount
    // the new scope first).
    widget.mediaSession?.detach(_coordinator);
    final catalog = _catalog;
    if (catalog != null) {
      widget.mediaSession?.detachCatalog(catalog);
    }
    WidgetsBinding.instance.removeObserver(this);
    _restoration.dispose();
    _preferencesController.dispose();
    _stateController.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }
}
