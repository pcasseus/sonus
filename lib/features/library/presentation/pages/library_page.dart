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
import '../models/library_navigation_memory.dart';
import '../widgets/roster/artist_roster.dart';
import 'artist_finder_page.dart';
import 'artist_profile_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.changes, this.navigationMemory});

  /// Reloads after library edits, imports and recorded listening; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;

  /// Where the Roster left off. When null: the app's (provided by the
  /// Library scope), else one of this page's own (screens and tests outside
  /// the app). Tests pass their own, with a controllable clock.
  final LibraryNavigationMemory? navigationMemory;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/// The Library: every listed artist in the Artist Roster (UI redesign L2),
/// with their statistics (D1), loaded once and refreshed only when the
/// library or listening history changes.
class _LibraryPageState extends State<LibraryPage> {
  LibraryChangeRefresher? _refresher;
  LibraryArtistsController? _controller;
  ArtistReelStatisticsController? _statistics;
  LibraryQueryRepository? _repository;

  /// The Roster's navigation session (App Update 1.1): its featured artist,
  /// kept across reloads and the Artist Profile. On entering the Library it
  /// comes from [_memory] (the artist left within the last 15 minutes) or
  /// is null, which starts the Roster on Page 1 with the first artist.
  String? _rosterArtistId;

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
      _rosterSort = ArtistStatisticsSort.qualifiedStreams;
      return false;
    }
    _rosterArtistId = kept.artistId;
    _rosterSort = kept.sort ?? ArtistStatisticsSort.qualifiedStreams;
    return true;
  }

  /// The Roster's search icon: the Artist Finder, which owns the keyboard.
  /// The chosen artist becomes the selection, previewed in the Roster.
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
      selectedArtistId: _rosterArtistId,
    );
    if (artist == null || !mounted) return;
    setState(() => _choose(artist.artistId));
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

  /// The Roster's featured artist (chosen, or its own default): the
  /// Roster's session remembers it.
  void _choose(String artistId) {
    _memory.rememberArtist(artistId);
    _rosterArtistId = artistId;
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
          // App Update 1.1: the Artist Roster is the Library's only artist
          // view (the Film Reel is kept for a future Sonus Wrapped).
          return ArtistRoster(
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
          );
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
