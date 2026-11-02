import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../charts/application/services/library_release_chart_eligibility.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/library_organization_service.dart';
import '../../application/models/analytics_time_window.dart';
import '../../application/services/analytics_behavior_metrics_service.dart';
import '../../application/services/analytics_entity_ranking_service.dart';
import '../../application/services/analytics_listening_duration_service.dart';
import '../../application/services/analytics_summary_service.dart';
import '../../application/services/pulse/pulse_entity_directory.dart';
import '../../application/services/pulse/pulse_insights_service.dart';
import '../../application/services/pulse/pulse_listening_records.dart';
import '../../application/services/year_in_sonus/year_in_sonus_service.dart';
import '../../data/pulse_preferences_store.dart';
import '../../data/repositories/sqlite_pulse_listening_records.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../controllers/pulse_insights_controller.dart';
import 'listening_artist_attribution_lookup.dart';

/// Provides the Sonus Pulse controller and the Year in Sonus loader its
/// Milestones card uses. Read-only over listening history; refreshes when
/// listening is recorded or the library changes.
class PulseInsightsScope extends StatefulWidget {
  const PulseInsightsScope({
    super.key,
    required this.child,
    this.changes,
    this.nowLocal,
  });

  final Widget child;
  final LibraryChangeSignal? changes;
  final DateTime Function()? nowLocal;

  @override
  State<PulseInsightsScope> createState() => _PulseInsightsScopeState();
}

class _PulseInsightsScopeState extends State<PulseInsightsScope> {
  AppDatabase? _database;
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;
  PlaybackListeningSegmentRepository? _segments;

  PulseInsightsController? _controller;
  YearInSonusLoader? _year;
  LibraryChangeRefresher? _refresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final database = context.watch<AppDatabase?>();
    final library = context.watch<LibraryQueryRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();
    final playbackSessions = context.watch<PlaybackSessionRepository?>();
    final segments = context.watch<PlaybackListeningSegmentRepository?>();
    if (identical(database, _database) &&
        identical(library, _library) &&
        identical(qualifiedPlays, _qualifiedPlays) &&
        identical(playbackSessions, _playbackSessions) &&
        identical(segments, _segments)) {
      return;
    }
    _database = database;
    _library = library;
    _qualifiedPlays = qualifiedPlays;
    _playbackSessions = playbackSessions;
    _segments = segments;
    _recreate();
  }

  void _recreate() {
    _refresher?.dispose();
    _refresher = null;
    _controller?.dispose();
    _controller = null;
    _year = null;

    final database = _database;
    final library = _library;
    final qualifiedPlays = _qualifiedPlays;
    final playbackSessions = _playbackSessions;
    final segments = _segments;
    if (database == null ||
        library == null ||
        qualifiedPlays == null ||
        playbackSessions == null ||
        segments == null) {
      return;
    }

    final attribution = listeningArtistAttributionOf(context);
    final organization = context.read<LibraryOrganizationService?>();
    final behavior = AnalyticsBehaviorMetricsService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    );
    final service = PulseInsightsService(
      records: _LazyRecords(database),
      artistAttribution: attribution,
      releaseEligibility: organization == null
          ? null
          : LibraryReleaseChartEligibility(organization),
      behaviorMetrics: behavior,
      nowLocal: widget.nowLocal,
    );
    final controller = PulseInsightsController(
      loader: service,
      preferences: PulsePreferencesStore(),
      directory: PulseEntityDirectoryService(
        library: library,
        playbackSessions: playbackSessions,
        statedReleaseFormats: organization == null
            ? null
            : () async => {
                for (final MapEntry(key: id, value: format)
                    in (await organization.releaseFormats()).entries)
                  id: format.label,
              },
      ),
      nowLocal: widget.nowLocal,
    );
    _controller = controller;
    _year = YearInSonusService(
      summaries: AnalyticsSummaryService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ),
      listeningDurations: AnalyticsListeningDurationService(
        listeningSegments: segments,
      ),
      behaviorMetrics: behavior,
      rankings: AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ),
      qualifiedPlays: qualifiedPlays,
      artistAttribution: attribution,
    );
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: {
        LibraryChangeKind.libraryEdited,
        LibraryChangeKind.listeningRecorded,
      },
      onChange: () => unawaited(controller.refresh()),
    );
    unawaited(controller.initialize());
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider<PulseInsightsController?>.value(
        value: _controller,
      ),
      Provider<YearInSonusLoader?>.value(value: _year),
    ],
    child: widget.child,
  );

  @override
  void dispose() {
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}

/// [SqlitePulseListeningRecords] over the app database, opened on first use.
class _LazyRecords implements PulseListeningRecords {
  _LazyRecords(this._database);

  final AppDatabase _database;
  Future<SqlitePulseListeningRecords>? _records;

  Future<SqlitePulseListeningRecords> get _ready =>
      _records ??= _database.database.then<SqlitePulseListeningRecords>(
        (Database db) => SqlitePulseListeningRecords(db),
      );

  @override
  Future<DateTime?> firstSessionStartedAt() async =>
      (await _ready).firstSessionStartedAt();

  @override
  Future<List<PulseSegmentRecord>> segmentsOverlapping(
    AnalyticsTimeWindow window,
  ) async => (await _ready).segmentsOverlapping(window);

  @override
  Future<List<PulsePlayRecord>> qualifiedPlays(
    AnalyticsTimeWindow window,
  ) async => (await _ready).qualifiedPlays(window);

  @override
  Future<List<PulsePlayRecord>> audibleSessions(
    AnalyticsTimeWindow window,
  ) async => (await _ready).audibleSessions(window);
}
