import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../analytics/domain/repositories/playback_listening_segment_repository.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../application/models/library_artist.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/library_organization_service.dart';
import '../controllers/artist_reel_statistics_controller.dart';
import '../controllers/library_artists_controller.dart';
import '../services/artist_library_statistics_service.dart';
import '../models/artist_library_statistics.dart';
import '../controllers/library_view_controller.dart';
import '../widgets/film_reel/artist_film_reel.dart';
import '../widgets/library_view_switch.dart';
import '../models/library_navigation_memory.dart';
import '../widgets/roster/artist_roster.dart';
import 'artist_finder_page.dart';
import 'artist_profile_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    this.changes,
    this.initialView = LibraryView.roster,
    this.navigationMemory,
  });

  /// Reloads after library edits, imports and recorded listening; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;

  /// The view shown first: the Artist Roster unless chosen otherwise.
  final LibraryView initialView;

  /// Where the Roster left off. When null: the app's (provided by the
  /// Library scope), else one of this page's own (screens and tests outside
  /// the app). Tests pass their own, with a controllable clock.
  final LibraryNavigationMemory? navigationMemory;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/// The Library: every listed artist in the Artist Roster (default) or the
/// Film Reel (UI redesign L1/L2), with their statistics (D1), loaded once
/// and refreshed only when the library or listening history changes. Both
/// views share one selection and open the same Artist Profile.
class _LibraryPageState extends State<LibraryPage> {
  LibraryChangeRefresher? _refresher;
  LibraryArtistsController? _controller;
  ArtistReelStatisticsController? _statistics;
  LibraryQueryRepository? _repository;

  /// The Roster's navigation session (App Update 1.1): its featured artist,
  /// kept across reloads, the Artist Profile and view switches. On entering
  /// the Library it comes from [_memory] (the artist left within the last
  /// 15 minutes) or is null, which starts the Roster on Page 1 with the
  /// first artist.
  String? _rosterArtistId;

  /// The Film Reel's centred artist. A choice in either view (a Roster
  /// tap, page or letter, a reel swipe, the Artist Finder) sets both, so
  /// the views show the same artist; the reel's own automatic first
  /// centring (when it has no artist yet) sets only this one, so it never
  /// moves the Roster from its default start.
  String? _reelArtistId;

  /// The Roster's sort, kept with the selection.
  ArtistStatisticsSort _rosterSort = ArtistStatisticsSort.qualifiedStreams;

  late final LibraryNavigationMemory _memory;

  /// A new Roster session (its state starts afresh) after the memory's
  /// window has passed while the app was in the background.
  int _rosterSession = 0;

  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _memory =
        widget.navigationMemory ??
        _optional<LibraryNavigationMemory>(context) ??
        LibraryNavigationMemory();
    _restore();
    // Sending the app to the background leaves the Roster too; coming back
    // after the window starts it again on Page 1.
    _lifecycle = AppLifecycleListener(
      onHide: _memory.leave,
      onShow: () {
        if (_restore() || !mounted) return;
        setState(() => _rosterSession++);
      },
    );
  }

  /// Restores what the memory kept; false when it starts afresh.
  bool _restore() {
    final kept = _memory.enter();
    if (kept == null) {
      _rosterArtistId = null;
      _reelArtistId = null;
      _rosterSort = ArtistStatisticsSort.qualifiedStreams;
      return false;
    }
    _rosterArtistId = kept.artistId;
    _reelArtistId = kept.artistId;
    _rosterSort = kept.sort ?? ArtistStatisticsSort.qualifiedStreams;
    return true;
  }

  /// The saved view, shared with Settings; without it (tests, previews)
  /// the view is [LibraryPage.initialView] and is not remembered.
  LibraryViewController? _viewController;

  /// The view on screen when there is no [_viewController].
  late LibraryView _localView = widget.initialView;

  LibraryView get _view => _viewController?.view ?? _localView;

  /// Shows [view]; with a [_viewController] it is also saved.
  void _switchView(LibraryView view) {
    final viewController = _viewController;
    if (viewController != null) {
      viewController.choose(view);
      return;
    }
    if (view == _localView) return;
    setState(() => _localView = view);
  }

  /// The search icon of either view: the Artist Finder, which owns the
  /// keyboard. The chosen artist becomes the selection, previewed in the
  /// Roster or centred in the Film Reel; the view does not change.
  Future<void> _findArtist() async {
    final controller = _controller;
    final statistics = _statistics;
    if (controller == null || statistics == null) return;
    final artist = await ArtistFinderPage.open(
      context,
      artists: controller.visibleArtists,
      statistics: statistics.snapshot,
      statisticsLoaded: statistics.hasLoaded,
      sort: _rosterSort,
      selectedArtistId: _view == LibraryView.roster
          ? _rosterArtistId
          : _reelArtistId,
    );
    if (artist == null || !mounted) return;
    setState(() => _choose(artist.artistId));
  }

  /// A provided notifier, rebuilt on its changes, or null without one.
  static T? _optionalNotifier<T extends ChangeNotifier>(BuildContext context) {
    try {
      return context.watch<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  static T? _optional<T extends Object>(BuildContext context) {
    try {
      return context.read<T?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _viewController = _optionalNotifier<LibraryViewController>(context);

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _refresher?.dispose();
    _controller?.dispose();
    _statistics?.dispose();

    _repository = repository;
    final organization = _optional<LibraryOrganizationService>(context);
    _controller = LibraryArtistsController(
      repository: repository,
      organization: organization,
    );
    final service =
        _optional<ArtistLibraryStatisticsService>(context) ??
        ArtistLibraryStatisticsService(
          library: repository,
          qualifiedPlays: _optional<QualifiedPlayRepository>(context),
          playbackSessions: _optional<PlaybackSessionRepository>(context),
          listeningSegments: _optional<PlaybackListeningSegmentRepository>(
            context,
          ),
          organization: organization,
        );
    _statistics = ArtistReelStatisticsController(load: service.load);

    final controller = _controller!;
    final statistics = _statistics!;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: LibraryChangeKind.values.toSet(),
      onChange: () {
        unawaited(controller.refresh());
        unawaited(statistics.refresh());
      },
    );
    unawaited(controller.load());
    unawaited(statistics.refresh());
  }

  /// An artist chosen (or the Roster's own featured artist): both views
  /// show it, and the Roster's session remembers it.
  void _choose(String artistId) {
    _memory.rememberArtist(artistId);
    _rosterArtistId = artistId;
    _reelArtistId = artistId;
  }

  /// The Film Reel's centred artist. Its automatic first centring (no
  /// artist yet) stays the reel's own; anything after is a choice.
  void _reelCentred(String artistId) {
    if (_reelArtistId == null) {
      _reelArtistId = artistId;
      return;
    }
    _choose(artistId);
  }

  void _openArtist(LibraryArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: artist.artistId,
          initialArtistName: artist.name,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      _controller?.refresh() ?? Future<void>.value(),
      _statistics?.refresh() ?? Future<void>.value(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final statistics = _statistics;

    if (controller == null || statistics == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-library'),
        child: Center(child: Text('Loading library…')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-library'),
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, statistics]),
        builder: (context, _) {
          if (controller.isLoading && controller.artists.isEmpty) {
            return const SonusStateView.loading();
          }

          if (controller.hasError && controller.artists.isEmpty) {
            return _LibraryLoadError(onRetry: controller.load);
          }

          final artists = controller.visibleArtists;

          if (artists.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LibraryEmptyState(),
                  ),
                ],
              ),
            );
          }

          final countLabel = sonusCount(artists.length, 'artist');
          return switch (_view) {
            LibraryView.roster => ArtistRoster(
              key: ValueKey<int>(_rosterSession),
              artists: artists,
              statistics: statistics.snapshot,
              statisticsLoaded: statistics.hasLoaded,
              countLabel: countLabel,
              selectedArtistId: _rosterArtistId,
              onSelected: _choose,
              onOpenArtist: _openArtist,
              sort: _rosterSort,
              onSortChanged: (sort) {
                _rosterSort = sort;
                _memory.rememberSort(sort);
              },
              onFind: _findArtist,
              onSwitchView: _switchView,
            ),
            LibraryView.filmReel => ArtistFilmReel(
              artists: artists,
              statistics: statistics.snapshot,
              statisticsLoaded: statistics.hasLoaded,
              countLabel: countLabel,
              selectedArtistId: _reelArtistId,
              onSelected: _reelCentred,
              onOpenArtist: _openArtist,
              onSwitchView: _switchView,
              onOpenSearch: _findArtist,
              onRefresh: _refresh,
            ),
          };
        },
      ),
    );
  }

  @override
  void dispose() {
    // Leaving the Library tab leaves the Roster: its memory's window starts.
    _memory.leave();
    _lifecycle?.dispose();
    _refresher?.dispose();
    _controller?.dispose();
    _statistics?.dispose();
    super.dispose();
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.library_music_outlined,
      title: 'No artists yet',
      message: 'Artists will appear here as music is added to your library.',
    );
  }
}

class _LibraryLoadError extends StatelessWidget {
  const _LibraryLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load your artists.',
      message: 'Try again to reload your library.',
      action: FilledButton.tonalIcon(
        onPressed: () {
          unawaited(onRetry());
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}
