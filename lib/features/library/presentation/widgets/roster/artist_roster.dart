import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../../../../core/design/sonus_artwork_palette.dart';
import '../../../../../core/design/sonus_cinematic_colors.dart';
import '../../../../../core/design/sonus_count_label.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_artwork_backdrop.dart';
import '../../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../../core/design/widgets/sonus_framed_artwork.dart';
import '../../../../../core/design/widgets/sonus_cinematic_atmosphere_builder.dart';
import '../../../../../core/design/widgets/sonus_glass_panel.dart';
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
/// The grid is sideways pages of portraits (D2); sort and A-Z move to the
/// page that holds what was asked for, and the search icon opens the Artist
/// Finder ([onFind]), which owns the keyboard. Every artist can also be
/// reached with the page buttons, so no gesture is ever required.
///
/// It lives in the Library tab, below the Sonus bar and above the
/// mini-player (Option C, after device QA): one row of controls, the
/// featured artist, two rows of portraits on phones, and SELECT ARTIST.
/// Statistics are never scaled down to fit; where they cannot show at
/// their size beside the portrait (narrow screens, large text), the Roster
/// scrolls instead, with SELECT ARTIST kept in place.
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
    this.onFind,
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

  /// Opens the Artist Finder; no search icon without it.
  final VoidCallback? onFind;

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
  late String? _previewId = _listedOrFirst(widget.selectedArtistId);

  String? _listedOrFirst(String? artistId) =>
      artistId != null && widget.artists.any((a) => a.artistId == artistId)
      ? artistId
      : (widget.artists.isEmpty ? null : widget.artists.first.artistId);
  late final ValueNotifier<String?> _previewArtwork = ValueNotifier(
    _preview == null ? null : ArtistFilmReel.portraitPath(_preview!),
  );

  PageController? _pages;
  int _perPage = 15;
  int _page = 0;
  bool _pageChosen = false;

  ArtistRosterView? _view;
  (ArtistStatisticsSort, Object, Object)? _viewKey;

  LibraryArtist? get _preview {
    final id = _previewId;
    if (id == null) return null;
    for (final artist in widget.artists) {
      if (artist.artistId == id) return artist;
    }
    return null;
  }

  ArtistRosterView get _rosterView {
    final key = (_sort, widget.artists, widget.statistics);
    if (_view == null || _viewKey != key) {
      _view = ArtistRosterView(
        artists: widget.artists,
        statistics: widget.statistics,
        sort: _sort,
      );
      _viewKey = key;
    }
    return _view!;
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
  }

  @override
  void dispose() {
    _pages?.dispose();
    _previewArtwork.dispose();
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
              bottom: false,
              child: Column(
                children: [
                  Expanded(child: _body(colors)),
                  _SelectButton(colors: colors, onPressed: _openPreview),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The page line under the grid (the artist count and the page): one
  /// line of small text and its padding.
  static double _pageLine(double textScale) => 8 + 16 * textScale;

  /// The featured header (V3): SELECT AN ARTIST, the full-width name and
  /// the rank with its padding: 83dp at normal text (Roboto, measured),
  /// generous above it (the name scales down before it grows past this).
  static double headerHeight(double textScale) => 83 * textScale;

  /// The height the featured row needs for its statistics at full size:
  /// two rows of tiles and the top track (Roboto, measured), with spacing.
  static double featuredNeeded(double textScale) => 160 * textScale + 22;

  /// The artwork's share of the featured row's width (V3: wider artwork,
  /// so group and cast photographs fill more of their frame).
  static const double artworkShare = 0.52;

  Widget _body(SonusCinematicColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final columns = width >= 600 ? 7 : (width >= 360 ? 5 : 4);
        const gap = 8.0;
        final gridWidth = width - _PageArrow.width * 2 - 8;
        final tileWidth = (gridWidth - gap * (columns - 1)) / columns;
        final tileHeight = tileWidth * 1.18;
        final rowStep = tileHeight + gap;
        final narrowControls = width < 360 || textScale >= 1.3;
        final controlsHeight = narrowControls ? 112.0 : 56.0;
        final header = headerHeight(textScale);
        final needed = featuredNeeded(textScale);

        // Two rows of portraits on phones (Option C); wide screens add rows
        // while the featured artist keeps generous room.
        var rows = 2;
        double gridHeight() =>
            rows * tileHeight + (rows - 1) * gap + _pageLine(textScale);
        var featuredRoom = height - controlsHeight - header - gridHeight();
        final maxRows = width >= 600 ? 4 : 2;
        while (rows < maxRows && featuredRoom - rowStep >= needed + 80) {
          rows++;
          featuredRoom -= rowStep;
        }
        final compact =
            textScale >= 1.3 || width < 330 || featuredRoom < needed;

        final preview = _preview;
        final stats = preview == null
            ? null
            : widget.statistics[preview.artistId];
        final featuredHeader = preview == null
            ? const SizedBox.shrink()
            : _FeaturedHeader(
                key: ValueKey<String>('roster-header-${preview.artistId}'),
                artist: preview,
                stats: stats,
                loaded: widget.statisticsLoaded,
                colors: colors,
              );
        final controls = _Controls(
          colors: colors,
          sort: _sort,
          narrow: narrowControls,
          onFind: widget.onFind,
          onSort: _setSort,
          onLetters: _chooseLetter,
          onSwitchView: widget.onSwitchView,
        );
        final grid = _grid(
          colors,
          columns: columns,
          rows: rows,
          tileWidth: tileWidth,
          tileHeight: tileHeight,
          gap: gap,
        );

        if (compact) {
          // Everything at its own size, scrolling; SELECT ARTIST stays put.
          return SingleChildScrollView(
            key: const ValueKey<String>('roster-compact'),
            child: Column(
              children: [
                controls,
                featuredHeader,
                // The portraits come before the artwork and statistics, so
                // the select grid is in view without scrolling past them.
                SizedBox(height: gridHeight() + 8, child: grid),
                if (preview != null)
                  _Featured(
                    artist: preview,
                    stats: stats,
                    loaded: widget.statisticsLoaded,
                    colors: colors,
                    compact: true,
                    onOpen: _openPreview,
                  ),
              ],
            ),
          );
        }

        // The featured artist takes what the controls and grid leave, up to
        // a little over half the space; the grid gets the rest.
        final featuredHeight = featuredRoom.clamp(needed, height * 0.55);
        return Column(
          children: [
            controls,
            featuredHeader,
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
            Expanded(child: grid),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.countLabel,
                  key: const ValueKey<String>('library-artist-count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                'Page ${_page + 1} of $count',
                key: const ValueKey<String>('roster-page-indicator'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The previewed artist: portrait, name, rank, statistics and top track.
/// The featured artist's artwork and statistics (V3): the artwork on
/// [_ArtistRosterState.artworkShare] of the width with an accent rim and
/// glow, the statistics beside it on glass. In the scrolling layout the
/// artwork leads and the statistics follow at full width.
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

  /// The featured artwork, as a button that opens the profile.
  Widget _openableArtwork(BuildContext context, double width) {
    final decoration = SonusTheme.of(context).decoration;
    return Semantics(
      button: true,
      label: 'Open ${artist.name}',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey<String>('roster-featured-open'),
        onTap: onOpen,
        child: DecoratedBox(
          key: const ValueKey<String>('roster-featured-frame'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: decoration.allowGradients
                  ? colors.accent.withValues(alpha: 0.7)
                  : colors.edge,
              width: 1.5,
            ),
            boxShadow: SonusGlow.shadows(
              colors.glow,
              decoration,
              blurRadius: 22,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: _Portrait(
              key: const ValueKey<String>('roster-featured-portrait'),
              artist: artist,
              width: width,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsPanel() => SonusGlassPanel(
    base: colors.surface,
    edge: colors.edge,
    glow: colors.glow,
    padding: const EdgeInsets.all(6),
    child: _StatsGrid(
      artist: artist,
      stats: stats,
      loaded: loaded,
      colors: colors,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final artworkWidth =
              (constraints.maxWidth - gap) * _ArtistRosterState.artworkShare;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: artworkWidth,
                child: _openableArtwork(context, artworkWidth),
              ),
              const SizedBox(width: gap),
              Expanded(
                // Its own size; clipped, never squeezed, if ever short.
                child: ClipRect(
                  child: OverflowBox(
                    // Centred beside the artwork when shorter than it.
                    alignment: Alignment.center,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    fit: OverflowBoxFit.deferToChild,
                    child: _statsPanel(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _compact(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = (constraints.maxWidth * 0.7).clamp(120.0, 280.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: _openableArtwork(context, size),
                ),
              ),
              const SizedBox(height: 12),
              _statsPanel(),
            ],
          );
        },
      ),
    );
  }
}

/// The featured artist's name across the full width (V3): SELECT AN
/// ARTIST, the name in bold italic display type, and the rank between two
/// rules, as on a select screen.
class _FeaturedHeader extends StatelessWidget {
  const _FeaturedHeader({
    super.key,
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
    final tokens = SonusTheme.of(context);
    final reduced =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);
    Widget rule({required bool leading}) => Expanded(
      child: ExcludeSemantics(
        child: Container(
          height: 1.5,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: leading
                  ? [colors.edge.withValues(alpha: 0), colors.accent]
                  : [colors.accent, colors.edge.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : tokens.motion.baseShort,
      child: Padding(
        key: ValueKey<String>('roster-header-body-${artist.artistId}'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SelectLabel(colors: colors),
            const SizedBox(height: 2),
            _Name(artist: artist, colors: colors),
            const SizedBox(height: 2),
            Row(
              children: [
                rule(leading: true),
                // May wrap with large text on narrow screens, never overflow.
                Flexible(
                  flex: 4,
                  child: _RankBadge(
                    stats: stats,
                    loaded: loaded,
                    colors: colors,
                  ),
                ),
                rule(leading: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// SELECT AN ARTIST, as on a select screen; for screen readers it names
/// the screen.
class _SelectLabel extends StatelessWidget {
  const _SelectLabel({required this.colors});

  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Artist Roster, select an artist',
      excludeSemantics: true,
      child: Text(
        'SELECT AN ARTIST',
        key: const ValueKey<String>('roster-select-label'),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 2.4,
          fontWeight: FontWeight.w700,
        ),
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
    final initials = _Initials(name: artist.name, colors: colors);
    // Decoded wide enough for an image that fills by trimming a little.
    final decodeWidth =
        (width /
                (1 - ArtworkFraming.defaultMaxCrop) *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: path == null
          ? initials
          // Group and cast photographs keep everyone in the frame: the
          // image fills the frame only when that trims little, and is
          // otherwise shown whole over a blur of itself.
          : SonusFramedArtwork(
              image: ResizeImage(FileImage(File(path)), width: decodeWidth),
              fill: colors.surface,
              fallback: initials,
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
        child: Text(
          artist.name.toUpperCase(),
          key: const ValueKey<String>('roster-featured-name'),
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
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

/// The featured artist's statistics (V3): releases, songs, streams and
/// listening time as a two-by-two grid of tiles, then the top track with
/// its artwork. Text is never scaled: values and labels wrap if they must.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
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
    final tileColour = colors.surface.withValues(alpha: 0.6);

    Widget tile(
      String key,
      IconData icon,
      String value,
      String label,
      String spoken,
    ) => Expanded(
      child: Semantics(
        label: spoken,
        excludeSemantics: true,
        child: Container(
          key: ValueKey<String>('roster-stat-$key'),
          padding: const EdgeInsets.fromLTRB(7, 5, 5, 5),
          decoration: BoxDecoration(
            color: tileColour,
            borderRadius: BorderRadius.circular(12),
          ),
          // The icon beside the value; the label below at the tile's
          // full width, so it keeps one line at full size.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 15, color: colors.accent),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                'releases',
                Icons.album_rounded,
                '${artist.albumCount}',
                sonusCountNoun(artist.albumCount, 'Release'),
                sonusCount(artist.albumCount, 'release'),
              ),
              const SizedBox(width: 6),
              tile(
                'songs',
                Icons.music_note_rounded,
                '${artist.songCount}',
                sonusCountNoun(artist.songCount, 'Song'),
                sonusCount(artist.songCount, 'song'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                'streams',
                Icons.bar_chart_rounded,
                loaded ? '$streams' : '–',
                sonusCountNoun(streams, 'Stream'),
                loaded ? sonusCount(streams, 'stream') : 'Streams loading',
              ),
              const SizedBox(width: 6),
              tile(
                'listened',
                Icons.schedule_rounded,
                loaded && hasListened ? sonusListeningTime(listened) : '–',
                'Listened',
                !loaded
                    ? 'Listening time loading'
                    : hasListened
                    ? '${sonusListeningTime(listened)} listened'
                    : 'No listening time yet',
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: top == null
              ? (loaded ? 'No top track yet' : 'Top track loading')
              : 'Top track: ${top.track.displayTitle}',
          excludeSemantics: true,
          child: Container(
            key: const ValueKey<String>('roster-top-track'),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: tileColour,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (top != null)
                  SonusArtworkImage(path: top.track.artworkPath, size: 34)
                else
                  Icon(Icons.star_rounded, color: colors.accent, size: 22),
                const SizedBox(width: 8),
                // Shortened with an ellipsis, never scaled.
                Flexible(
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
        ),
      ],
    );
  }
}

/// The Roster's one row of controls (Option C): find, sort, A-Z and the
/// switch to the Film Reel. Two rows on narrow screens and with large text.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.colors,
    required this.sort,
    required this.narrow,
    required this.onFind,
    required this.onSort,
    required this.onLetters,
    required this.onSwitchView,
  });

  final SonusCinematicColors colors;
  final ArtistStatisticsSort sort;
  final bool narrow;
  final VoidCallback? onFind;
  final ValueChanged<ArtistStatisticsSort> onSort;
  final VoidCallback onLetters;
  final ValueChanged<LibraryView>? onSwitchView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onFind = this.onFind;
    final onSwitchView = this.onSwitchView;
    Widget squareButton({
      required Key key,
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
    }) => Material(
      color: colors.surface.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.edge),
      ),
      child: IconButton(
        key: key,
        tooltip: tooltip,
        color: colors.textPrimary,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
    final find = onFind == null
        ? null
        : squareButton(
            key: const ValueKey<String>('roster-find'),
            tooltip: 'Find an artist',
            icon: Icons.search_rounded,
            onPressed: onFind,
          );
    final toReel = onSwitchView == null
        ? null
        : Semantics(
            button: true,
            label: '${LibraryView.filmReel.label} view',
            excludeSemantics: true,
            child: squareButton(
              key: const ValueKey<String>('library-view-reel'),
              tooltip: 'Show the ${LibraryView.filmReel.label}',
              icon: LibraryView.filmReel.icon,
              onPressed: () => onSwitchView(LibraryView.filmReel),
            ),
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

    if (!narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          children: [
            if (find != null) ...[find, const SizedBox(width: 8)],
            Expanded(child: sortMenu),
            const SizedBox(width: 8),
            letters,
            if (toReel != null) ...[const SizedBox(width: 8), toReel],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (find != null) ...[find, const SizedBox(width: 8)],
              Expanded(child: letters),
              if (toReel != null) ...[const SizedBox(width: 8), toReel],
            ],
          ),
          const SizedBox(height: 8),
          sortMenu,
        ],
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
  /// Narrow, so the portraits get the width; the button itself stays a
  /// 48dp target, overhanging the grid's margins.
  static const double width = 32;

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
      width: width,
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: width, minHeight: 48),
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
