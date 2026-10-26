import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../library/application/repositories/library_query_repository.dart';
import 'listening_artist_attribution_lookup.dart';
import '../../application/services/analytics_behavior_metrics_service.dart';
import '../../application/services/analytics_entity_ranking_service.dart';
import '../../application/services/analytics_listening_duration_service.dart';
import '../../application/services/analytics_summary_service.dart';
import '../../application/services/year_in_sonus/year_in_sonus_enrichment_service.dart';
import '../../application/services/year_in_sonus/year_in_sonus_service.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../controllers/year_in_sonus_controller.dart';

class YearInSonusScope extends StatefulWidget {
  const YearInSonusScope({super.key, required this.child, this.now});

  final Widget child;
  final YearInSonusNow? now;

  @override
  State<YearInSonusScope> createState() => _YearInSonusScopeState();
}

class _YearInSonusScopeState extends State<YearInSonusScope> {
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;
  PlaybackListeningSegmentRepository? _listeningSegments;

  YearInSonusController? _controller;

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
  void didUpdateWidget(YearInSonusScope oldWidget) {
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

    final attribution = listeningArtistAttributionOf(context);
    final service = YearInSonusService(
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
      qualifiedPlays: qualifiedPlays,
      artistAttribution: attribution,
    );

    final controller = YearInSonusController(
      service: service,
      enrichment: YearInSonusEnrichmentService(
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
    return ChangeNotifierProvider<YearInSonusController?>.value(
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
