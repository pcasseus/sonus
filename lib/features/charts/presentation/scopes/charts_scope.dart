import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/services/all_time_chart_service.dart';
import '../../application/services/all_time_moment_service.dart';
import '../../application/services/chart_finalization_service.dart';
import '../../application/services/chart_snapshot_builder_service.dart';
import '../../data/repositories/sqlite_chart_moment_repository.dart';
import '../../data/repositories/sqlite_chart_repository.dart';
import '../controllers/charts_controller.dart';

class ChartsScope extends StatefulWidget {
  const ChartsScope({super.key, required this.child, this.now, this.changes});

  final Widget child;

  /// Reloads after recorded listening, imports and library edits; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;
  final ChartsControllerNow? now;

  @override
  State<ChartsScope> createState() => _ChartsScopeState();
}

class _ChartsScopeState extends State<ChartsScope> {
  AppDatabase? _database;
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;

  ChartsController? _controller;
  LibraryChangeRefresher? _refresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final database = context.watch<AppDatabase>();
    final library = context.watch<LibraryQueryRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();
    final playbackSessions = context.watch<PlaybackSessionRepository?>();

    if (identical(database, _database) &&
        identical(library, _library) &&
        identical(qualifiedPlays, _qualifiedPlays) &&
        identical(playbackSessions, _playbackSessions)) {
      return;
    }

    _database = database;
    _library = library;
    _qualifiedPlays = qualifiedPlays;
    _playbackSessions = playbackSessions;

    _recreateController();
  }

  @override
  void didUpdateWidget(ChartsScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.now, widget.now)) {
      _recreateController();
    }
  }

  void _recreateController() {
    final previousController = _controller;
    _controller = null;

    _refresher?.dispose();
    _refresher = null;
    previousController?.dispose();

    final database = _database;
    final library = _library;
    final qualifiedPlays = _qualifiedPlays;
    final playbackSessions = _playbackSessions;

    if (database == null ||
        library == null ||
        qualifiedPlays == null ||
        playbackSessions == null) {
      return;
    }

    final charts = SqliteChartRepository(database);

    final moments = SqliteChartMomentRepository(database);
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      charts: charts,
      playbackSessions: playbackSessions,
    );

    final allTimeCharts = AllTimeChartService(
      qualifiedPlays: qualifiedPlays,
      library: library,
    );
    final finalization = ChartFinalizationService(
      builder: builder,
      charts: charts,
      qualifiedPlays: qualifiedPlays,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime(2026, 9, 27).toUtc(),
      // A pass that spans a restore must not write what it read before it.
      restoreGeneration: () => database.mutationCoordinator.restoreGeneration,
    );

    final allTimeMoments = AllTimeMomentService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      moments: moments,
      // SN-45 release week: earlier achievements are never told as news.
      activationUtc: DateTime(2026, 10, 25).toUtc(),
      restoreGeneration: () => database.mutationCoordinator.restoreGeneration,
    );

    final controller = ChartsController(
      allTimeCharts: allTimeCharts,
      finalization: finalization,
      charts: charts,
      library: library,
      moments: moments,
      allTimeMoments: allTimeMoments,
      now: widget.now,
    );

    _controller = controller;
    // New qualified plays move the all-time chart; imports and edits change
    // titles, artwork and membership. Never sent for playback progress.
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: LibraryChangeKind.values.toSet(),
      onChange: () => unawaited(controller.refresh()),
    );

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChartsController?>.value(
      value: _controller,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}
