import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/controllers/playback_analytics_controller.dart';
import '../../application/services/listening_session_recovery_service.dart';
import '../../application/services/listening_session_tracker.dart';
import '../../data/daos/playback_listening_segment_dao.dart';
import '../../data/daos/playback_session_dao.dart';
import '../../data/daos/qualified_play_dao.dart';
import '../../data/repositories/listening_session_mutation_transaction_runner.dart';
import '../../data/repositories/sqlite_playback_listening_segment_repository.dart';
import '../../data/repositories/sqlite_playback_session_repository.dart';
import '../../data/repositories/sqlite_qualified_play_repository.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';

typedef AnalyticsScopeNow = DateTime Function();

class AnalyticsRuntime {
  const AnalyticsRuntime({
    required this.playbackSessions,
    required this.listeningSegments,
    required this.qualifiedPlays,
    required this.controller,
  });

  final PlaybackSessionRepository playbackSessions;
  final PlaybackListeningSegmentRepository listeningSegments;
  final QualifiedPlayRepository qualifiedPlays;
  final PlaybackAnalyticsController controller;

  static Future<AnalyticsRuntime> create({
    required AppDatabase appDatabase,
    required PlaybackCoordinator playbackCoordinator,
    AnalyticsScopeNow? now,
    PlaybackAnalyticsUserIdProvider? userIdProvider,
  }) async {
    final database = await appDatabase.database;

    final playbackSessions = SqlitePlaybackSessionRepository(
      PlaybackSessionDao(database),
    );

    final listeningSegments = SqlitePlaybackListeningSegmentRepository(
      PlaybackListeningSegmentDao(database),
    );

    final qualifiedPlays = SqliteQualifiedPlayRepository(
      QualifiedPlayDao(database),
    );

    final recovery = ListeningSessionRecoveryService(
      playbackSessions: playbackSessions,
      listeningSegments: listeningSegments,
    );

    await recovery.recoverInterruptedSessions();

    final tracker = ListeningSessionTracker(
      playbackSessions: playbackSessions,
      listeningSegments: listeningSegments,
      qualifiedPlays: qualifiedPlays,
      mutationRunner: ListeningSessionMutationTransactionRunner(
        appDatabase: appDatabase,
      ),
      now: now,
    );

    final controller = PlaybackAnalyticsController(
      playbackCoordinator: playbackCoordinator,
      tracker: tracker,
      now: now,
      userIdProvider: userIdProvider,
    );

    return AnalyticsRuntime(
      playbackSessions: playbackSessions,
      listeningSegments: listeningSegments,
      qualifiedPlays: qualifiedPlays,
      controller: controller,
    );
  }

  Future<void> dispose() => controller.dispose();
}

class AnalyticsScope extends StatefulWidget {
  const AnalyticsScope({
    super.key,
    required this.child,
    this.now,
    this.userIdProvider,
  });

  final Widget child;
  final AnalyticsScopeNow? now;
  final PlaybackAnalyticsUserIdProvider? userIdProvider;

  @override
  State<AnalyticsScope> createState() => _AnalyticsScopeState();
}

class _AnalyticsScopeState extends State<AnalyticsScope> {
  AppDatabase? _database;
  PlaybackCoordinator? _playbackCoordinator;
  AnalyticsRuntime? _runtime;

  int _initializationVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();
    final playbackCoordinator = context.read<PlaybackCoordinator>();

    if (identical(database, _database) &&
        identical(playbackCoordinator, _playbackCoordinator)) {
      return;
    }

    _database = database;
    _playbackCoordinator = playbackCoordinator;

    final previousRuntime = _runtime;
    _runtime = null;

    if (previousRuntime != null) {
      unawaited(previousRuntime.dispose());
    }

    final version = ++_initializationVersion;

    unawaited(
      _initializeAnalytics(
        appDatabase: database,
        playbackCoordinator: playbackCoordinator,
        version: version,
      ),
    );
  }

  Future<void> _initializeAnalytics({
    required AppDatabase appDatabase,
    required PlaybackCoordinator playbackCoordinator,
    required int version,
  }) async {
    final runtime = await AnalyticsRuntime.create(
      appDatabase: appDatabase,
      playbackCoordinator: playbackCoordinator,
      now: widget.now,
      userIdProvider: widget.userIdProvider,
    );

    if (!mounted || version != _initializationVersion) {
      await runtime.dispose();
      return;
    }

    setState(() {
      _runtime = runtime;
    });
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;

    return MultiProvider(
      providers: [
        Provider<PlaybackSessionRepository?>.value(
          value: runtime?.playbackSessions,
        ),
        Provider<PlaybackListeningSegmentRepository?>.value(
          value: runtime?.listeningSegments,
        ),
        Provider<QualifiedPlayRepository?>.value(
          value: runtime?.qualifiedPlays,
        ),
        Provider<PlaybackAnalyticsController?>.value(
          value: runtime?.controller,
        ),
      ],
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _initializationVersion++;

    final runtime = _runtime;

    if (runtime != null) {
      unawaited(runtime.dispose());
    }

    super.dispose();
  }
}
