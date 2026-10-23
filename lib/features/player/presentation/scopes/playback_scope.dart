import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../application/controllers/playback_coordinator.dart';
import '../../application/controllers/playback_preferences_controller.dart';
import '../../data/daos/track_lyrics_dao.dart';
import '../../data/engines/just_audio_playback_engine.dart';
import '../../data/repositories/sqlite_track_lyrics_repository.dart';
import '../../data/services/playback_preferences_store.dart';
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
  });

  final Widget child;
  final PlaybackEngineFactory? engineFactory;

  /// Overrides the device preference store (tests).
  final PlaybackPreferencesStore? preferencesStore;

  @override
  State<PlaybackScope> createState() => _PlaybackScopeState();
}

class _PlaybackScopeState extends State<PlaybackScope> {
  late final PlaybackEngine _engine;
  late final PlaybackCoordinator _coordinator;
  late final PlaybackStateController _stateController;
  late final PlaybackPreferencesController _preferencesController;

  AppDatabase? _database;
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
    unawaited(_preferencesController.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();

    if (identical(database, _database)) {
      return;
    }

    _database = database;

    final version = ++_initializationVersion;

    unawaited(_initializeLyrics(appDatabase: database, version: version));
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
    _preferencesController.dispose();
    _stateController.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }
}
