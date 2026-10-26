import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/events/library_change_signal.dart';

import '../../../library/application/repositories/library_query_repository.dart';
import 'listening_artist_attribution_lookup.dart';
import '../../application/services/analytics_behavior_metrics_service.dart';
import '../../application/services/analytics_entity_ranking_service.dart';
import '../../application/services/analytics_listening_duration_service.dart';
import '../../application/services/analytics_summary_service.dart';
import '../../application/services/monthly_insights/monthly_entity_listening_duration_service.dart';
import '../../application/services/monthly_insights/monthly_listening_distribution_service.dart';
import '../../application/services/monthly_insights/monthly_listening_insights_enrichment_service.dart';
import '../../application/services/monthly_insights/monthly_listening_insights_service.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../controllers/monthly_listening_insights_controller.dart';

class MonthlyListeningInsightsScope extends StatefulWidget {
  const MonthlyListeningInsightsScope({
    super.key,
    required this.child,
    this.now,
    this.changes,
  });

  final Widget child;

  /// Reloads after library or listening changes; the shared signal if null.
  final LibraryChangeSignal? changes;
  final MonthlyListeningInsightsNow? now;

  @override
  State<MonthlyListeningInsightsScope> createState() =>
      _MonthlyListeningInsightsScopeState();
}

class _MonthlyListeningInsightsScopeState
    extends State<MonthlyListeningInsightsScope> {
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;
  PlaybackListeningSegmentRepository? _listeningSegments;

  MonthlyListeningInsightsController? _controller;
  LibraryChangeRefresher? _refresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final library = context.watch<LibraryQueryRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();
    final playbackSessions = context.watch<PlaybackSessionRepository?>();
    final listeningSegments = context
        .watch<PlaybackListeningSegmentRepository?>();

    if (identical(library, _library) &&
        identical(qualifiedPlays, _qualifiedPlays) &&
        identical(playbackSessions, _playbackSessions) &&
        identical(listeningSegments, _listeningSegments)) {
      return;
    }

    _library = library;
    _qualifiedPlays = qualifiedPlays;
    _playbackSessions = playbackSessions;
    _listeningSegments = listeningSegments;

    _recreateController();
  }

  @override
  void didUpdateWidget(MonthlyListeningInsightsScope oldWidget) {
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

    final library = _library;
    final qualifiedPlays = _qualifiedPlays;
    final playbackSessions = _playbackSessions;
    final listeningSegments = _listeningSegments;

    if (library == null ||
        qualifiedPlays == null ||
        playbackSessions == null ||
        listeningSegments == null) {
      return;
    }

    final attribution = listeningArtistAttributionOf(context);
    final service = MonthlyListeningInsightsService(
      summaries: AnalyticsSummaryService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ),
      listeningDurations: AnalyticsListeningDurationService(
        listeningSegments: listeningSegments,
      ),
      behaviorMetrics: AnalyticsBehaviorMetricsService(
        playbackSessions: playbackSessions,
        qualifiedPlays: qualifiedPlays,
      ),
      rankings: AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ),
      entityListeningDurations: MonthlyEntityListeningDurationService(
        playbackSessions: playbackSessions,
        listeningSegments: listeningSegments,
        artistAttribution: attribution,
      ),
      distribution: MonthlyListeningDistributionService(
        qualifiedPlays: qualifiedPlays,
        listeningSegments: listeningSegments,
      ),
    );

    final controller = MonthlyListeningInsightsController(
      service: service,
      enrichment: MonthlyListeningInsightsEnrichmentService(
        library: library,
        playbackSessions: playbackSessions,
      ),
      now: widget.now,
    );

    _controller = controller;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: {
        LibraryChangeKind.libraryEdited,
        LibraryChangeKind.listeningRecorded,
      },
      onChange: () => unawaited(controller.refresh()),
    );

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MonthlyListeningInsightsController?>.value(
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
