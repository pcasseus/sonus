import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_artwork_palette.dart';
import '../../../../../core/design/sonus_cinematic_colors.dart';
import '../../../../../core/design/sonus_count_label.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_artwork_backdrop.dart';
import '../../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../../core/design/widgets/sonus_cinematic_atmosphere_builder.dart';
import '../../../../../core/design/widgets/sonus_glass_panel.dart';
import '../../../../../core/design/widgets/sonus_perspective_panel.dart';
import '../../../application/models/library_artist.dart';
import '../../models/alphabet_index.dart';
import '../../models/artist_library_statistics.dart';
import '../../models/artist_roster_view.dart';
import '../film_reel/artist_film_reel.dart';
import '../library_view_switch.dart';

/// The Artist Roster (UI redesign L2), the Library's default screen: a
/// fighting-game style character select over the Library's artists.
/// Tapping a portrait previews the artist above the grid; tapping the
/// featured portrait or SELECT ARTIST opens their Artist Profile
/// ([onOpenArtist]). The previewed artist is the Library's selection, shared
/// with the Film Reel ([selectedArtistId], [onSelected]).
///
/// The grid is sideways pages of portraits (D2); search, sort and A-Z move
/// to the page that holds what was asked for. Every artist can also be
/// reached with the page buttons, so no gesture is ever required.
class ArtistRoster extends StatefulWidget {
  const ArtistRoster({
    super.key,
    required this.artists,
    required this.statistics,
    required this.statisticsLoaded,
    required this.selectedArtistId,
    required this.onSelected,
    required this.onOpenArtist,
    required this.countLabel,
    this.sort = ArtistStatisticsSort.qualifiedStreams,
    this.onSortChanged,
    this.searchRequest = 0,
    this.onSwitchView,
    this.artworkPalette,
  });

  /// The Library's artists (its visibility rules already applied). Never
  /// empty.
  final List<LibraryArtist> artists;
  final ArtistLibraryStatisticsSnapshot statistics;
  final bool statisticsLoaded;

  /// The artist to preview: the Library's selection; the first when null
  /// or no longer listed.
  final String? selectedArtistId;

  /// Called when another artist is previewed.
  final ValueChanged<String> onSelected;

  /// Opens the Artist Profile of the featured artist.
  final ValueChanged<LibraryArtist> onOpenArtist;

  /// The header's artist count, such as "12 artists".
  final String countLabel;

  final ArtistStatisticsSort sort;

  /// Remembers the sort for the next time the Roster is shown.
  final ValueChanged<ArtistStatisticsSort>? onSortChanged;

  /// Focuses the search field each time it changes (the Film Reel's search
  /// icon, D11).
  final int searchRequest;

  /// Switches the Library to another view; no switch without it.
  final ValueChanged<LibraryView>? onSwitchView;

  final SonusArtworkPalette? artworkPalette;

  /// Sort labels, as on the sort menu.
  static String sortLabel(ArtistStatisticsSort sort) => switch (sort) {
    ArtistStatisticsSort.name => 'Name',
    ArtistStatisticsSort.qualifiedStreams => 'Most Played',
    ArtistStatisticsSort.listeningTime => 'Listening Time',
    ArtistStatisticsSort.recentlyAdded => 'Recently Added',
  };

  @override
  State<ArtistRoster> createState() => _ArtistRosterState();
}

class _ArtistRosterState extends State<ArtistRoster> {
  late ArtistStatisticsSort _sort = widget.sort;
  String _query = '';
  late String? _previewId = _listedOrFirst(widget.selectedArtistId);

  String? _listedOrFirst(String? artistId) =>
      artistId != null && widget.artists.any((a) => a.artistId == artistId)
      ? artistId
      : (widget.artists.isEmpty ? null : widget.artists.first.artistId);
  late final ValueNotifier<String?> _previewArtwork = ValueNotifier(
    _preview == null ? null : ArtistFilmReel.portraitPath(_preview!),
  );
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  PageController? _pages;
  int _perPage = 15;
  int _page = 0;
  bool _pageChosen = false;

  ArtistRosterView? _view;
  (ArtistStatisticsSort, String, Object, Object)? _viewKey;

  LibraryArtist? get _preview {
    final id = _previewId;
    if (id == null) return null;
    for (final artist in widget.artists) {
      if (artist.artistId == id) return artist;
    }
    return null;
  }

  ArtistRosterView get _rosterView {
    final key = (_sort, _query, widget.artists, widget.statistics);
    if (_view == null || _viewKey != key) {
      _view = ArtistRosterView(
        artists: widget.artists,
        statistics: widget.statistics,
        sort: _sort,
        query: _query,
      );
      _viewKey = key;
    }
    return _view!;
  }

  /// Whether the last build used the search layout.
  bool _wasSearching = false;

  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  /// The search layout (UI fix after device QA): while the search field
  /// has focus and the keyboard is open, the featured artist, statistics
  /// and SELECT ARTIST give way so the matches get the space left above
  /// the keyboard. Read from the view itself, so it holds however the
  /// screens above have consumed the inset.
  bool _searching(BuildContext context) {
    // Also rebuild when the inset changes without a change of size.
    MediaQuery.maybeViewInsetsOf(context);
    return _searchFocus.hasFocus && View.of(context).viewInsets.bottom > 0;
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
    if (widget.searchRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(ArtistRoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wanted = _listedOrFirst(widget.selectedArtistId ?? _previewId);
    if (wanted != _previewId || !identical(widget.artists, oldWidget.artists)) {
      final changed = wanted != _previewId;
      _previewId = wanted;
      _previewArtwork.value = _preview == null
          ? null
          : ArtistFilmReel.portraitPath(_preview!);
      if (changed && wanted != null) {
        _jumpAfterBuild(_rosterView.pageOf(wanted, _perPage) ?? 0);
      }
      if (wanted != null && wanted != widget.selectedArtistId) {
        // Report the artist now previewed after a reload.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSelected(wanted);
        });
      }
    }
    if (widget.searchRequest != oldWidget.searchRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    _previewArtwork.dispose();
    _search.dispose();
    _searchFocus.removeListener(_onSearchFocus);
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _reduceMotion {
    final tokens = SonusTheme.of(context);
    return tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);
  }

  void _previewArtist(LibraryArtist artist) {
    if (artist.artistId == _previewId) return;
    setState(() => _previewId = artist.artistId);
    _previewArtwork.value = ArtistFilmReel.portraitPath(artist);
    widget.onSelected(artist.artistId);
  }

  /// Picking a match while searching previews it and closes the keyboard,
  /// so the full Roster shows the artist; the search stays.
  void _pickMatch(LibraryArtist artist) {
    _previewArtist(artist);
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _search.clear();
    _setQuery('');
  }

  void _goToPage(int page) {
    final pages = _pages;
    final count = _rosterView.pageCount(_perPage);
    final target = page.clamp(0, count - 1);
    if (pages == null || !pages.hasClients) {
      setState(() => _page = target);
      return;
    }
    if (_reduceMotion) {
      pages.jumpToPage(target);
    } else {
      final tokens = SonusTheme.of(context);
      unawaited(
        pages.animateToPage(
          target,
          duration: tokens.motion.baseMedium,
          curve: tokens.motion.curve,
        ),
      );
    }
  }

  void _jumpAfterBuild(int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pages = _pages;
      if (pages != null && pages.hasClients) {
        pages.jumpToPage(page);
      } else {
        setState(() => _page = page);
      }
    });
  }

  void _setQuery(String query) {
    setState(() {
      _query = query;
      _page = 0;
    });
    // The results start on the first page.
    _jumpAfterBuild(0);
  }

  void _setSort(ArtistStatisticsSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    widget.onSortChanged?.call(sort);
    // Follow the previewed artist to its place in the new order.
    final page = _previewId == null
        ? 0
        : _rosterView.pageOf(_previewId!, _perPage) ?? 0;
    _jumpAfterBuild(page);
  }

  Future<void> _chooseLetter() async {
    final letter = await showDialog<String>(
      context: context,
      builder: (context) =>
          _LetterPicker(available: _rosterViewByName().alphabet.available),
    );
    if (letter == null || !mounted) return;
    // A-Z follows names, so it lists by name first.
    if (_sort != ArtistStatisticsSort.name) {
      setState(() => _sort = ArtistStatisticsSort.name);
      widget.onSortChanged?.call(ArtistStatisticsSort.name);
    }
    final first = _rosterView.firstFor(letter);
    if (first == null) return;
    final page = _rosterView.pageOf(first.artistId, _perPage) ?? 0;
    _jumpAfterBuild(page);
  }

  ArtistRosterView _rosterViewByName() => _sort == ArtistStatisticsSort.name
      ? _rosterView
      : ArtistRosterView(
          artists: widget.artists,
          statistics: widget.statistics,
          sort: ArtistStatisticsSort.name,
          query: _query,
        );

  /// SELECT ARTIST and the featured portrait open the Artist Profile.
  void _openPreview() {
    final artist = _preview;
    if (artist != null) widget.onOpenArtist(artist);
  }

  /// The page controller for [perPage] portraits a page, recreated (on the
  /// previewed artist's page) when the grid's size changes.
  PageController _controllerFor(int perPage) {
    final current = _pages;
    if (current != null && perPage == _perPage) return current;
    final view = _rosterView;
    final page = !_pageChosen && _previewId != null
        ? view.pageOf(_previewId!, perPage) ?? 0
        : (_page * _perPage ~/ perPage).clamp(0, view.pageCount(perPage) - 1);
    _perPage = perPage;
    _page = page;
    _pageChosen = true;
    final replacement = PageController(initialPage: page);
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _pages = replacement;
  }

  @override
  Widget build(BuildContext context) {
    return SonusCinematicAtmosphereBuilder.listenable(
      artworkPath: _previewArtwork,
      palette: widget.artworkPalette,
      builder: (context, colors) => Material(
        key: const ValueKey<String>('artist-roster'),
        color: colors.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: _previewArtwork,
              builder: (context, path, _) => SonusArtworkBackdrop(
                artworkPath: path,
                top: colors.background,
                bottom: colors.backgroundDeep,
              ),
            ),
            SafeArea(
              top: false,
              bottom: false,
              // Rebuilt whenever the space changes, which is what opening
              // or closing the keyboard does.
              child: LayoutBuilder(
                builder: (context, _) {
                  final searching = _searching(context);
                  if (_wasSearching && !searching) {
                    // Back to the full Roster, on the previewed artist.
                    final id = _previewId;
                    final page = id == null
                        ? 0
                        : _rosterView.pageOf(id, _perPage) ?? 0;
                    _jumpAfterBuild(page);
                  }
                  _wasSearching = searching;
                  return Column(
                    children: [
                      _RosterHeader(
                        colors: colors,
                        countLabel: widget.countLabel,
                        onSwitchView: widget.onSwitchView,
                      ),
                      Expanded(
                        child: searching ? _searchBody(colors) : _body(colors),
                      ),
                      if (!searching)
                        _SelectButton(colors: colors, onPressed: _openPreview),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(SonusCinematicColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final compact = textScale >= 1.3 || height < 520 || width < 330;
        final columns = width >= 600 ? 7 : (width >= 360 ? 5 : 4);
        const arrows = 40.0;
        const gap = 8.0;
        final gridWidth = width - arrows * 2 - 8;
        final tileWidth = (gridWidth - gap * (columns - 1)) / columns;
        final tileHeight = tileWidth * 1.18;
        final preview = _preview;
        final stats = preview == null
            ? null
            : widget.statistics[preview.artistId];
        final toolbar = _toolbar(colors);

        if (compact) {
          final rows = 2;
          final grid = _grid(
            colors,
            columns: columns,
            rows: rows,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            gap: gap,
          );
          return SingleChildScrollView(
            key: const ValueKey<String>('roster-compact'),
            child: Column(
              children: [
                if (preview != null)
                  _Featured(
                    artist: preview,
                    stats: stats,
                    loaded: widget.statisticsLoaded,
                    colors: colors,
                    compact: true,
                    onOpen: _openPreview,
                  ),
                toolbar,
                SizedBox(
                  height: tileHeight * rows + gap * (rows - 1) + 40,
                  child: grid,
                ),
              ],
            ),
          );
        }

        final featuredHeight = height * 0.44;
        final gridHeight = height - featuredHeight - 64;
        // About three rows on phones, as on the reference; four on wide
        // screens.
        final rows = ((gridHeight - 28 + gap) / (tileHeight + gap))
            .floor()
            .clamp(1, width >= 600 ? 4 : 3);
        return Column(
          children: [
            SizedBox(
              height: featuredHeight,
              child: preview == null
                  ? const SizedBox.shrink()
                  : _Featured(
                      artist: preview,
                      stats: stats,
                      loaded: widget.statisticsLoaded,
                      colors: colors,
                      compact: false,
                      onOpen: _openPreview,
                    ),
            ),
            toolbar,
            Expanded(
              child: _grid(
                colors,
                columns: columns,
                rows: rows,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                gap: gap,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(SonusCinematicColors colors) => _Toolbar(
    colors: colors,
    search: _search,
    searchFocus: _searchFocus,
    sort: _sort,
    onQuery: _setQuery,
    onClear: _clearSearch,
    onSort: _setSort,
    onLetters: _chooseLetter,
  );

  /// While typing with the keyboard open: the search bar, then every match
  /// in a grid that scrolls in the space left above the keyboard.
  Widget _searchBody(SonusCinematicColors colors) {
    final view = _rosterView;
    final theme = Theme.of(context);
    final hasQuery = _query.trim().isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 600 ? 7 : (width >= 360 ? 5 : 4);
        const gap = 8.0;
        const padding = 12.0;
        final tileWidth = (width - padding * 2 - gap * (columns - 1)) / columns;
        return CustomScrollView(
          key: const ValueKey<String>('roster-search-results'),
          slivers: [
            // Only the field while typing: sort and A-Z return with the
            // full Roster, leaving the matches as much room as possible.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: _Toolbar.searchField(
                  context,
                  colors: colors,
                  search: _search,
                  searchFocus: _searchFocus,
                  onQuery: _setQuery,
                  onClear: _clearSearch,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  view.isEmpty
                      ? 'No artists match "$_query"'
                      : hasQuery
                      ? sonusCount(
                          view.artists.length,
                          'match',
                          plural: 'matches',
                        )
                      : sonusCount(view.artists.length, 'artist'),
                  key: ValueKey<String>(
                    view.isEmpty ? 'roster-no-results' : 'roster-match-count',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(padding, 0, padding, 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio: 1 / 1.18,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final artist = view.artists[index];
                  return _RosterTile(
                    key: ValueKey<String>('roster-tile-${artist.artistId}'),
                    artist: artist,
                    stats: widget.statistics[artist.artistId],
                    loaded: widget.statisticsLoaded,
                    selected: artist.artistId == _previewId,
                    colors: colors,
                    width: tileWidth,
                    onTap: () => _pickMatch(artist),
                  );
                }, childCount: view.artists.length),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(
    SonusCinematicColors colors, {
    required int columns,
    required int rows,
    required double tileWidth,
    required double tileHeight,
    required double gap,
  }) {
    final view = _rosterView;
    final perPage = columns * rows;
    final pages = _controllerFor(perPage);
    final count = view.pageCount(perPage);
    final theme = Theme.of(context);

    if (view.isEmpty) {
      return Center(
        child: Text(
          'No artists match "$_query"',
          key: const ValueKey<String>('roster-no-results'),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _PageArrow(
                key: const ValueKey<String>('roster-page-previous'),
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous page',
                colors: colors,
                onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
              ),
              Expanded(
                child: PageView.builder(
                  key: const ValueKey<String>('roster-pages'),
                  controller: pages,
                  itemCount: count,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, page) {
                    final artists = view.page(page, perPage);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var row = 0; row < rows; row++) ...[
                            if (row > 0) SizedBox(height: gap),
                            SizedBox(
                              height: tileHeight,
                              child: Row(
                                children: [
                                  for (var col = 0; col < columns; col++) ...[
                                    if (col > 0) SizedBox(width: gap),
                                    Expanded(
                                      child: () {
                                        final i = row * columns + col;
                                        if (i >= artists.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final artist = artists[i];
                                        return _RosterTile(
                                          key: ValueKey<String>(
                                            'roster-tile-${artist.artistId}',
                                          ),
                                          artist: artist,
                                          stats: widget
                                              .statistics[artist.artistId],
                                          loaded: widget.statisticsLoaded,
                                          selected:
                                              artist.artistId == _previewId,
                                          colors: colors,
                                          width: tileWidth,
                                          onTap: () => _previewArtist(artist),
                                        );
                                      }(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              _PageArrow(
                key: const ValueKey<String>('roster-page-next'),
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next page',
                colors: colors,
                onPressed: _page < count - 1
                    ? () => _goToPage(_page + 1)
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            'Page ${_page + 1} of $count',
            key: const ValueKey<String>('roster-page-indicator'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader({
    required this.colors,
    required this.countLabel,
    required this.onSwitchView,
  });

  final SonusCinematicColors colors;
  final String countLabel;
  final ValueChanged<LibraryView>? onSwitchView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSwitchView = this.onSwitchView;
    Widget rule() => Expanded(
      child: ExcludeSemantics(
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.edge.withValues(alpha: 0), colors.edge],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          rule(),
          Flexible(
            flex: 3,
            child: Column(
              children: [
                Semantics(
                  header: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Artist Roster',
                      maxLines: 1,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SELECT AN ARTIST',
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 2.4,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    countLabel,
                    key: const ValueKey<String>('library-artist-count'),
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          rule(),
          if (onSwitchView != null)
            LibraryViewSwitch(
              current: LibraryView.roster,
              onChanged: onSwitchView,
              colors: colors,
            ),
        ],
      ),
    );
  }
}

/// The previewed artist: portrait, name, rank, statistics and top track.
class _Featured extends StatelessWidget {
  const _Featured({
    required this.artist,
    required this.stats,
    required this.loaded,
    required this.colors,
    required this.compact,
    required this.onOpen,
  });

  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final SonusCinematicColors colors;
  final bool compact;

  /// Opens the artist's profile.
  final VoidCallback onOpen;

  /// The featured portrait, as a button that opens the profile.
  Widget _openablePortrait(double width) => Semantics(
    button: true,
    label: 'Open ${artist.name}',
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey<String>('roster-featured-open'),
      onTap: onOpen,
      child: _Portrait(
        key: const ValueKey<String>('roster-featured-portrait'),
        artist: artist,
        width: width,
        colors: colors,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final reduced =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : tokens.motion.baseShort,
      child: KeyedSubtree(
        key: ValueKey<String>('roster-featured-${artist.artistId}'),
        child: compact ? _compact(context) : _full(context),
      ),
    );
  }

  Widget _full(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final portraitWidth = constraints.maxWidth * 0.46;
        return Stack(
          children: [
            // The ghost: a faint, larger copy behind, as on a select
            // screen.
            Positioned(
              left: -portraitWidth * 0.18,
              top: 0,
              bottom: 0,
              width: portraitWidth * 1.1,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.18,
                  child: _Portrait(
                    artist: artist,
                    width: portraitWidth,
                    colors: colors,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 6,
              bottom: 6,
              width: portraitWidth,
              child: _openablePortrait(portraitWidth),
            ),
            Positioned(
              left: portraitWidth + 18,
              right: 12,
              top: 4,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: _Name(artist: artist, colors: colors),
                  ),
                  const SizedBox(height: 6),
                  _RankBadge(stats: stats, loaded: loaded, colors: colors),
                  const SizedBox(height: 8),
                  Flexible(
                    flex: 3,
                    child: SonusPerspectivePanel(
                      angle: -0.16,
                      alignment: Alignment.centerRight,
                      child: SonusGlassPanel(
                        base: colors.surface,
                        edge: colors.edge,
                        glow: colors.glow,
                        padding: const EdgeInsets.all(10),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topLeft,
                          child: _StatsList(
                            artist: artist,
                            stats: stats,
                            loaded: loaded,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _compact(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, height: 140, child: _openablePortrait(110)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Name(artist: artist, colors: colors),
                    const SizedBox(height: 6),
                    _RankBadge(stats: stats, loaded: loaded, colors: colors),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SonusGlassPanel(
            base: colors.surface,
            edge: colors.edge,
            padding: const EdgeInsets.all(12),
            child: _StatsList(
              artist: artist,
              stats: stats,
              loaded: loaded,
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    super.key,
    required this.artist,
    required this.width,
    required this.colors,
  });

  final LibraryArtist artist;
  final double width;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final path = ArtistFilmReel.portraitPath(artist);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: path == null
          ? _Initials(name: artist.name, colors: colors)
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.35),
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  _Initials(name: artist.name, colors: colors),
            ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.artist, required this.colors});

  final LibraryArtist artist;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final decoration = SonusTheme.of(context).decoration;
    return Semantics(
      header: true,
      label: artist.name,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            artist.name.toUpperCase(),
            key: const ValueKey<String>('roster-featured-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              height: 1.0,
              letterSpacing: -0.5,
              shadows: decoration.allowGlow && colors.hasGlow
                  ? [Shadow(color: colors.glow, blurRadius: 18)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.stats,
    required this.loaded,
    required this.colors,
  });

  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final rank = stats?.rank;
    final text = !loaded
        ? 'RANK –'
        : rank == null
        ? 'UNRANKED'
        : '#$rank ARTIST RANK';
    return Semantics(
      label: !loaded
          ? 'Rank loading'
          : rank == null
          ? 'Unranked'
          : 'Ranked number $rank among your artists',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey<String>('roster-rank'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.military_tech_rounded, color: colors.accent, size: 20),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({
    required this.artist,
    required this.stats,
    required this.loaded,
    required this.colors,
  });

  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streams = stats?.qualifiedStreams ?? 0;
    final listened = stats?.listened;
    final hasListened = listened != null && listened > Duration.zero;
    final top = stats?.topTrack;

    Widget row(IconData icon, String value, String label, String spoken) =>
        Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            // Wraps onto a second line rather than overflowing with large
            // text.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Icon(icon, size: 18, color: colors.accent),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row(
          Icons.album_rounded,
          '${artist.albumCount}',
          sonusCountNoun(artist.albumCount, 'Release'),
          sonusCount(artist.albumCount, 'release'),
        ),
        row(
          Icons.music_note_rounded,
          '${artist.songCount}',
          sonusCountNoun(artist.songCount, 'Song'),
          sonusCount(artist.songCount, 'song'),
        ),
        row(
          Icons.bar_chart_rounded,
          loaded ? '$streams' : '–',
          sonusCountNoun(streams, 'Stream'),
          loaded ? sonusCount(streams, 'stream') : 'Streams loading',
        ),
        row(
          Icons.schedule_rounded,
          loaded && hasListened ? sonusListeningTime(listened) : '–',
          'Listened',
          !loaded
              ? 'Listening time loading'
              : hasListened
              ? '${sonusListeningTime(listened)} listened'
              : 'No listening time yet',
        ),
        const SizedBox(height: 6),
        Semantics(
          label: top == null
              ? (loaded ? 'No top track yet' : 'Top track loading')
              : 'Top track: ${top.track.displayTitle}',
          excludeSemantics: true,
          child: Row(
            key: const ValueKey<String>('roster-top-track'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (top != null)
                SonusArtworkImage(path: top.track.artworkPath, size: 40)
              else
                Icon(Icons.star_rounded, color: colors.accent, size: 22),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      top?.track.displayTitle ?? '–',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Top Track',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.colors,
    required this.search,
    required this.searchFocus,
    required this.sort,
    required this.onQuery,
    required this.onClear,
    required this.onSort,
    required this.onLetters,
  });

  final SonusCinematicColors colors;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ArtistStatisticsSort sort;
  final ValueChanged<String> onQuery;
  final VoidCallback onClear;
  final ValueChanged<ArtistStatisticsSort> onSort;
  final VoidCallback onLetters;

  /// The search field, alone or in the toolbar.
  static Widget searchField(
    BuildContext context, {
    required SonusCinematicColors colors,
    required TextEditingController search,
    required FocusNode searchFocus,
    required ValueChanged<String> onQuery,
    required VoidCallback onClear,
  }) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.edge),
    );
    return TextField(
      key: const ValueKey<String>('roster-search'),
      controller: search,
      focusNode: searchFocus,
      onChanged: onQuery,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search artists…',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        ),
        prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: search,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  key: const ValueKey<String>('roster-search-clear'),
                  tooltip: 'Clear search',
                  color: colors.textSecondary,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
        ),
        filled: true,
        fillColor: colors.surface.withValues(alpha: 0.7),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = searchField(
      context,
      colors: colors,
      search: search,
      searchFocus: searchFocus,
      onQuery: onQuery,
      onClear: onClear,
    );
    final sortMenu = PopupMenuButton<ArtistStatisticsSort>(
      key: const ValueKey<String>('roster-sort'),
      tooltip: 'Sort artists',
      initialValue: sort,
      onSelected: onSort,
      itemBuilder: (context) => [
        for (final option in ArtistStatisticsSort.values)
          PopupMenuItem<ArtistStatisticsSort>(
            key: ValueKey<String>('roster-sort-${option.name}'),
            value: option,
            child: Text(ArtistRoster.sortLabel(option)),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Sort: ${ArtistRoster.sortLabel(sort)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
    final letters = Material(
      color: colors.accent.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.accent),
      ),
      child: InkWell(
        key: const ValueKey<String>('roster-az'),
        borderRadius: BorderRadius.circular(14),
        onTap: onLetters,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'A–Z',
                semanticsLabel: 'Jump to a letter',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
          if (constraints.maxWidth >= 360 && textScale < 1.3) {
            return Row(
              children: [
                Expanded(flex: 5, child: field),
                const SizedBox(width: 8),
                Flexible(flex: 4, child: sortMenu),
                const SizedBox(width: 8),
                letters,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: sortMenu),
                  const SizedBox(width: 8),
                  letters,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A slanted portrait in the selection grid.
class _RosterTile extends StatelessWidget {
  const _RosterTile({
    super.key,
    required this.artist,
    required this.stats,
    required this.loaded,
    required this.selected,
    required this.colors,
    required this.width,
    required this.onTap,
  });

  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final bool selected;
  final SonusCinematicColors colors;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = SonusTheme.of(context).decoration;
    final path = ArtistFilmReel.portraitPath(artist);
    final rank = stats?.rank;
    final standing = !loaded
        ? ''
        : rank == null
        ? ', unranked'
        : ', ranked number $rank';

    final shape = _SlantBorder(
      slant: 0.14,
      side: BorderSide(
        color: selected ? colors.accent : colors.edge.withValues(alpha: 0.5),
        width: selected ? 2.5 : 1,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${artist.name}$standing',
      hint: selected ? 'Previewing' : 'Preview this artist',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: selected
              ? SonusGlow.shadows(colors.glow, decoration, blurRadius: 16)
              : null,
        ),
        child: Material(
          color: colors.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: path == null
                ? _Initials(name: artist.name, colors: colors, small: true)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.35),
                    // Decoded at tile size: a page of portraits stays cheap.
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) => _Initials(
                      name: artist.name,
                      colors: colors,
                      small: true,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A parallelogram leaning right by [slant] of its height.
class _SlantBorder extends ShapeBorder {
  const _SlantBorder({required this.slant, this.side = BorderSide.none});

  final double slant;
  final BorderSide side;

  Path _path(Rect rect) {
    final shift = rect.height * slant;
    return Path()
      ..moveTo(rect.left + shift, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - shift, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      _SlantBorder(slant: slant, side: side.scale(t));
}

class _Initials extends StatelessWidget {
  const _Initials({
    required this.name,
    required this.colors,
    this.small = false,
  });

  final String name;
  final SonusCinematicColors colors;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
              .toUpperCase();
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.all(small ? 6 : 16),
            child: Text(
              initials,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageArrow extends StatelessWidget {
  const _PageArrow({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final SonusCinematicColors colors;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: colors.textPrimary,
        disabledColor: colors.textSecondary.withValues(alpha: 0.35),
        iconSize: 30,
        padding: EdgeInsets.zero,
        icon: Icon(icon),
      ),
    );
  }
}

/// The big confirm button, with chamfered ends and speed lines.
class _SelectButton extends StatelessWidget {
  const _SelectButton({required this.colors, required this.onPressed});

  final SonusCinematicColors colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final decoration = SonusTheme.of(context).decoration;
    final theme = Theme.of(context);
    const shape = _ChamferBorder();

    Widget speedLines() => ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 5,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              transform: Matrix4.skewX(-0.5),
              color: colors.accent.withValues(alpha: 0.75 - i * 0.2),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          speedLines(),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                shadows: SonusGlow.shadows(colors.glow, decoration),
              ),
              child: Material(
                shape: const _ChamferBorder(),
                clipBehavior: Clip.antiAlias,
                color: colors.accent,
                child: InkWell(
                  key: const ValueKey<String>('roster-select'),
                  onTap: onPressed,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        // Always one line, so the button never pushes the
                        // grid off screen; scaled down only when needed.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'SELECT ARTIST',
                            maxLines: 1,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.onAccent,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          speedLines(),
        ],
      ),
    );
  }
}

/// A rectangle with its four corners cut at 45 degrees.
class _ChamferBorder extends ShapeBorder {
  const _ChamferBorder();

  Path _path(Rect rect) {
    final cut = rect.height * 0.32;
    return Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - cut, rect.top)
      ..lineTo(rect.right, rect.top + cut)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + cut, rect.bottom)
      ..lineTo(rect.left, rect.bottom - cut)
      ..lineTo(rect.left, rect.top + cut)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// The A-Z picker: every letter is a button, letters without artists are
/// disabled.
class _LetterPicker extends StatelessWidget {
  const _LetterPicker({required this.available});

  final Set<String> available;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jump to a letter'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final letter in AlphabetIndex.letters)
              SizedBox(
                width: 48,
                height: 48,
                child: TextButton(
                  key: ValueKey<String>('roster-letter-$letter'),
                  onPressed: available.contains(letter)
                      ? () => Navigator.of(context).pop(letter)
                      : null,
                  child: Text(letter),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
