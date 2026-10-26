import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/events/library_change_signal.dart';

import '../../../analytics/application/services/analytics_artist_listening_duration_service.dart';
import '../../../analytics/application/services/analytics_entity_ranking_service.dart';
import '../../../analytics/domain/repositories/playback_listening_segment_repository.dart';
import '../../../analytics/presentation/scopes/listening_artist_attribution_lookup.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../application/services/home_data_service.dart';
import '../controllers/home_controller.dart';

class HomeScope extends StatefulWidget {
  const HomeScope({super.key, required this.child, this.now, this.changes});

  final Widget child;

  /// Reloads after library or listening changes; the shared signal if null.
  final LibraryChangeSignal? changes;
  final HomeControllerNow? now;

  @override
  State<HomeScope> createState() => _HomeScopeState();
}

class _HomeScopeState extends State<HomeScope> {
  LibraryQueryRepository? _library;
  QualifiedPlayRepository? _qualifiedPlays;
  PlaybackSessionRepository? _playbackSessions;
  PlaybackListeningSegmentRepository? _listeningSegments;

  HomeController? _controller;
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
  void didUpdateWidget(HomeScope oldWidget) {
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
    final service = HomeDataService(
      library: library,
      analyticsRankings: AnalyticsEntityRankingService(
        qualifiedPlays: qualifiedPlays,
        artistAttribution: attribution,
      ),
      artistListeningDurations: AnalyticsArtistListeningDurationService(
        playbackSessions: playbackSessions,
        listeningSegments: listeningSegments,
        artistAttribution: attribution,
      ),
    );

    final controller = HomeController(service: service, now: widget.now);

    _controller = controller;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: {
        LibraryChangeKind.libraryEdited,
        LibraryChangeKind.importCompleted,
        LibraryChangeKind.listeningRecorded,
      },
      onChange: () => unawaited(controller.refresh()),
    );

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeController?>.value(
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
