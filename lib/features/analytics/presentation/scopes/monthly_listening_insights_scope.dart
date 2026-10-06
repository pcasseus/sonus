import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../library/application/repositories/library_query_repository.dart';
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
  });

  final Widget child;
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

    final service = MonthlyListeningInsightsService(
      summaries: AnalyticsSummaryService(qualifiedPlays: qualifiedPlays),
      listeningDurations: AnalyticsListeningDurationService(
        listeningSegments: listeningSegments,
      ),
      behaviorMetrics: AnalyticsBehaviorMetricsService(
        playbackSessions: playbackSessions,
        qualifiedPlays: qualifiedPlays,
      ),
      rankings: AnalyticsEntityRankingService(qualifiedPlays: qualifiedPlays),
      entityListeningDurations: MonthlyEntityListeningDurationService(
        playbackSessions: playbackSessions,
        listeningSegments: listeningSegments,
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
    _controller?.dispose();
    super.dispose();
  }
}
