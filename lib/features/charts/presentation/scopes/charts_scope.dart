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
import '../../application/services/moment_rules_activation.dart';
import '../../application/services/this_week_chart_service.dart';
import '../../application/services/moments_last_seen_store.dart';
import '../../data/repositories/sqlite_chart_moment_repository.dart';
import '../../data/repositories/sqlite_chart_repository.dart';
import '../../data/services/shared_preferences_moment_rules_activation_store.dart';
import '../../data/services/shared_preferences_moments_last_seen_store.dart';
import '../controllers/charts_controller.dart';
import '../../../library/application/services/library_organization_service.dart';
import '../../application/services/library_release_chart_eligibility.dart';
import '../../../analytics/presentation/scopes/listening_artist_attribution_lookup.dart';
import '../../../analytics/application/services/listening_artist_attribution.dart';
import '../../../song_stats/application/song_listening_records.dart';
import '../../../song_stats/application/song_stats_service.dart';
import '../../../song_stats/data/sqlite_song_listening_records.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';

class ChartsScope extends StatefulWidget {
  const ChartsScope({
    super.key,
    required this.child,
    this.now,
    this.changes,
    this.momentsLastSeen,
    this.momentRulesActivation,
  });

  final Widget child;

  /// Reloads after recorded listening, imports and library edits; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;
  final ChartsControllerNow? now;

  /// Remembers when Moments was last open; device preferences if null.
  final MomentsLastSeenStore? momentsLastSeen;

  /// Which Moments rules apply; device preferences and the build's
  /// approval if null.
  final MomentRulesActivation? momentRulesActivation;

  @override
  State<ChartsScope> createState() => _ChartsScopeState();
}

class _ChartsScopeState extends State<ChartsScope> {
  AppDatabase? _database;
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;

  ChartsController? _controller;
  SongStatsLoader? _songStats;
  LibraryChangeRefresher? _refresher;

  /// One per process, so its instant is recorded once however often
  /// scopes and controllers are recreated.
  static final MomentRulesActivation _deviceRulesActivation = () {
    final store = SharedPreferencesMomentRulesActivationStore();
    return MomentRulesActivation(
      store: store,
      devicePolish: store,
      chronicle: store,
    );
  }();

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

  /// Every song and release by id, with the artist it counts for.
  static Future<Map<String, String>> _entityArtists(
    LibraryQueryRepository library,
    ListeningArtistAttribution? attribution,
  ) async {
    final attributor = await ArtistAttributor.of(attribution);
    return {
      for (final track in await library.getTracks())
        track.songId: attributor.artistFor(
          artistId: track.artistId,
          albumId: track.albumId,
        ),
      for (final album in await library.getAlbums())
        album.albumId: album.artistId,
    };
  }

  static LibraryOrganizationService? _organizationOf(BuildContext context) {
    try {
      return context.read<LibraryOrganizationService?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _recreateController() {
    final previousController = _controller;
    _controller = null;
    _songStats = null;

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
    final organization = _organizationOf(context);
    final attribution = listeningArtistAttributionOf(context);
    final releaseEligibility = organization == null
        ? null
        : LibraryReleaseChartEligibility(organization);
    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      charts: charts,
      playbackSessions: playbackSessions,
    );

    final allTimeCharts = AllTimeChartService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      playbackSessions: playbackSessions,
      releaseEligibility: releaseEligibility,
    );
    final finalization = ChartFinalizationService(
      builder: builder,
      charts: charts,
      qualifiedPlays: qualifiedPlays,
      moments: moments,
      momentsActivationWeekStartUtc: DateTime(2026, 9, 27).toUtc(),
      // A pass that spans a restore must not write what it read before it.
      restoreGeneration: () => database.mutationCoordinator.restoreGeneration,
      releaseEligibility: releaseEligibility,
      artistAttribution: () => _entityArtists(library, attribution),
      // Snapshot and Moments in one transaction (SN-50 F6).
      weekFinalizer: charts,
    );

    final allTimeMoments = AllTimeMomentService(
      qualifiedPlays: qualifiedPlays,
      library: library,
      moments: moments,
      playbackSessions: playbackSessions,
      // SN-45 release week: earlier achievements are never told as news.
      activationUtc: DateTime(2026, 10, 25).toUtc(),
      restoreGeneration: () => database.mutationCoordinator.restoreGeneration,
      releaseEligibility: releaseEligibility,
      artistAttribution: attribution,
    );

    final controller = ChartsController(
      allTimeCharts: allTimeCharts,
      finalization: finalization,
      charts: charts,
      library: library,
      moments: moments,
      allTimeMoments: allTimeMoments,
      now: widget.now,
      releaseFormats: organization?.releaseFormatsForDisplay,
      releaseEditions: switch (library) {
        final ReleaseEditionQueryRepository editions =>
          editions.getReleaseEditions,
        _ => null,
      },
      thisWeekCharts: ThisWeekChartService(
        builder: builder,
        releaseEligibility: releaseEligibility,
      ),
      momentsLastSeen:
          widget.momentsLastSeen ?? SharedPreferencesMomentsLastSeenStore(),
      playEdition: (playId) async =>
          (await qualifiedPlays.getById(playId))?.albumEditionId,
      momentRules:
          (widget.momentRulesActivation ?? _deviceRulesActivation).rules,
    );

    _controller = controller;

    // Song Stats (Charts 2.0 C4): read-only, from the same chart history,
    // the same provisional week rules and Pulse's listening definitions.
    final thisWeekSongs = ThisWeekChartService(
      builder: builder,
      releaseEligibility: releaseEligibility,
    );
    final now = widget.now ?? DateTime.now;
    Future<SongListeningRecords>? songRecords;
    _songStats = SongStatsService(
      charts: charts,
      library: library,
      records: () => songRecords ??= database.database.then(
        (db) => SqliteSongListeningRecords(db),
      ),
      // The week the chart already built when it is current; otherwise
      // the same provisional week, built the same way.
      liveSongs: () async =>
          controller.loadedLiveSongWeek(now()) ??
          await thisWeekSongs.load(
            chartType: ChartType.songs,
            referenceLocal: now(),
          ),
      // The career standings the Charts page opens on, ranked the same way
      // (#1–200), so a row's rank there matches Song Stats.
      careerSongs: () => allTimeCharts.load(
        chartType: ChartType.songs,
        referenceLocal: now(),
        viewSize: ChartViewSize.top200,
      ),
      nowLocal: now,
    );

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
    return Provider<SongStatsLoader?>.value(
      value: _songStats,
      child: ChangeNotifierProvider<ChartsController?>.value(
        value: _controller,
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}
