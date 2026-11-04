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
import '../../models/artist_library_statistics.dart';

/// The Library's artist Film Reel (UI redesign L1): one large portrait at a
/// time, the previous and next artists peeking above and below, and two
/// angled glass panels with the centred artist's statistics, over the
/// artwork's cinematic colours (D3).
///
/// Swiping vertically moves between artists; tapping the centred portrait
/// opens it ([onOpenArtist]), tapping a neighbour centres it. Statistics
/// come from [statistics] (D1), never recomputed here; only the centred
/// and neighbouring portraits are built and decoded.
///
/// On narrow screens, with large text, or when short, the panels sit flat
/// under the reel instead of beside the portrait, so nothing is clipped.
class ArtistFilmReel extends StatefulWidget {
  const ArtistFilmReel({
    super.key,
    required this.artists,
    required this.statistics,
    required this.statisticsLoaded,
    required this.countLabel,
    required this.onSelected,
    required this.onOpenArtist,
    this.selectedArtistId,
    this.onOpenRoster,
    this.onOpenSearch,
    this.onRefresh,
    this.artworkPalette,
  });

  /// The artists, in reel order. Never empty.
  final List<LibraryArtist> artists;

  final ArtistLibraryStatisticsSnapshot statistics;

  /// False until the statistics have loaded once; values show "–" until
  /// then.
  final bool statisticsLoaded;

  /// The header's artist count, such as "12 artists".
  final String countLabel;

  /// The artist to centre; the first when null or no longer listed.
  final String? selectedArtistId;

  /// Called when another artist is centred.
  final ValueChanged<String> onSelected;

  final ValueChanged<LibraryArtist> onOpenArtist;

  /// Opens the Artist Roster (L2); the button is disabled without it.
  final VoidCallback? onOpenRoster;

  /// Opens the Roster's artist search (D11); no search button without it.
  final VoidCallback? onOpenSearch;

  final Future<void> Function()? onRefresh;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? artworkPalette;

  /// The portrait the reel shows: the artist's portrait, else their banner
  /// (as the Library always has).
  static String? portraitPath(LibraryArtist artist) {
    for (final path in [
      artist.topArtistsArtworkPath,
      artist.headerArtworkPath,
    ]) {
      final trimmed = path?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Portrait shape: width over height.
  static const double cardAspect = 0.6;

  @override
  State<ArtistFilmReel> createState() => _ArtistFilmReelState();
}

class _ArtistFilmReelState extends State<ArtistFilmReel> {
  PageController? _pages;
  late int _index;
  late final ValueNotifier<String?> _centredArtwork;

  @override
  void initState() {
    super.initState();
    _index = _indexOf(widget.selectedArtistId);
    _centredArtwork = ValueNotifier<String?>(
      ArtistFilmReel.portraitPath(widget.artists[_index]),
    );
  }

  int _indexOf(String? artistId) {
    if (artistId == null) return 0;
    final index = widget.artists.indexWhere((a) => a.artistId == artistId);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(ArtistFilmReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After a reload the centred artist stays centred, wherever it moved
    // in the list; if it left, the reel stays at the same place.
    final centred = oldWidget
        .artists[_index.clamp(0, oldWidget.artists.length - 1)]
        .artistId;
    final wanted = widget.selectedArtistId ?? centred;
    var index = widget.artists.indexWhere((a) => a.artistId == wanted);
    if (index < 0) index = _index.clamp(0, widget.artists.length - 1);
    if (index != _index) {
      _index = index;
      final pages = _pages;
      if (pages != null && pages.hasClients) pages.jumpToPage(index);
    }
    _centredArtwork.value = ArtistFilmReel.portraitPath(widget.artists[_index]);
    final id = widget.artists[_index].artistId;
    if (id != widget.selectedArtistId) {
      // Report the artist now centred after a reload.
      scheduleMicrotask(() {
        if (mounted) widget.onSelected(id);
      });
    }
  }

  PageController _controllerFor(double viewportFraction) {
    final current = _pages;
    if (current != null &&
        (current.viewportFraction - viewportFraction).abs() < 0.005) {
      return current;
    }
    final replacement = PageController(
      initialPage: _index,
      viewportFraction: viewportFraction,
    );
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _pages = replacement;
  }

  void _centre(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _centredArtwork.value = ArtistFilmReel.portraitPath(widget.artists[index]);
    widget.onSelected(widget.artists[index].artistId);
  }

  void _goTo(int index) {
    final pages = _pages;
    if (pages == null || !pages.hasClients) return;
    if (index < 0 || index >= widget.artists.length) return;
    final tokens = SonusTheme.of(context);
    final reduced =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      pages.jumpToPage(index);
    } else {
      unawaited(
        pages.animateToPage(
          index,
          duration: tokens.motion.baseMedium,
          curve: tokens.motion.curve,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    _centredArtwork.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SonusCinematicAtmosphereBuilder.listenable(
      artworkPath: _centredArtwork,
      palette: widget.artworkPalette,
      builder: (context, colors) => Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: _centredArtwork,
            builder: (context, path, _) => SonusArtworkBackdrop(
              artworkPath: path,
              top: colors.background,
              bottom: colors.backgroundDeep,
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                _ReelHeader(
                  countLabel: widget.countLabel,
                  colors: colors,
                  onOpenRoster: widget.onOpenRoster,
                  onOpenSearch: widget.onOpenSearch,
                ),
                Expanded(child: _body(context, colors)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, SonusCinematicColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final compact = width < 360 || height < 460 || textScale >= 1.3;

        final stats = widget.statistics[widget.artists[_index].artistId];
        final key = ValueKey<String>(widget.artists[_index].artistId);

        if (compact) {
          final statsArea = _StatsArea(
            key: const ValueKey<String>('film-reel-stats-below'),
            colors: colors,
            artist: widget.artists[_index],
            stats: stats,
            loaded: widget.statisticsLoaded,
            identity: key,
            width: width,
            textScale: textScale,
          );
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, reel) {
                    final cardHeight = reel.maxHeight * 0.74;
                    final cardWidth = [
                      cardHeight * ArtistFilmReel.cardAspect,
                      width * 0.62,
                    ].reduce((a, b) => a < b ? a : b);
                    return _reel(
                      context,
                      colors,
                      height: reel.maxHeight,
                      cardWidth: cardWidth,
                      cardHeight: cardWidth / ArtistFilmReel.cardAspect,
                    );
                  },
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * 0.46),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: statsArea,
                ),
              ),
            ],
          );
        }

        var cardHeight = height * 0.6;
        var cardWidth = cardHeight * ArtistFilmReel.cardAspect;
        if (cardWidth > width * 0.54) {
          cardWidth = width * 0.54;
          cardHeight = cardWidth / ArtistFilmReel.cardAspect;
        }
        const overlap = 14.0;
        final side = (width - cardWidth) / 2;
        final panelWidth = (side - 6 + overlap).clamp(0.0, 136.0);
        final panelHeight = cardHeight * 0.84;
        final panelTop = (height - panelHeight) / 2;

        return Stack(
          children: [
            Positioned(
              left: side + overlap - panelWidth,
              top: panelTop,
              width: panelWidth,
              height: panelHeight,
              child: _SidePanel(
                key: const ValueKey<String>('film-reel-panel-left'),
                angle: 0.28,
                hinge: Alignment.centerRight,
                colors: colors,
                identity: key,
                children: _leftStats(stats, colors),
              ),
            ),
            Positioned(
              right: side + overlap - panelWidth,
              top: panelTop,
              width: panelWidth,
              height: panelHeight,
              child: _SidePanel(
                key: const ValueKey<String>('film-reel-panel-right'),
                angle: -0.28,
                hinge: Alignment.centerLeft,
                colors: colors,
                identity: key,
                children: _rightStats(stats, colors),
              ),
            ),
            Positioned.fill(
              child: _reel(
                context,
                colors,
                height: height,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _leftStats(
    ArtistLibraryStatistics? stats,
    SonusCinematicColors colors,
  ) {
    final artist = widget.artists[_index];
    return [
      _StatItem(
        key: const ValueKey<String>('film-reel-releases'),
        icon: Icons.album_rounded,
        value: '${artist.albumCount}',
        label: sonusCountNoun(artist.albumCount, 'Release'),
        semanticsLabel: sonusCount(artist.albumCount, 'release'),
        colors: colors,
      ),
      _StatItem(
        key: const ValueKey<String>('film-reel-songs'),
        icon: Icons.music_note_rounded,
        value: '${artist.songCount}',
        label: sonusCountNoun(artist.songCount, 'Song'),
        semanticsLabel: sonusCount(artist.songCount, 'song'),
        colors: colors,
      ),
      _rankItem(stats, colors),
    ];
  }

  Widget _rankItem(
    ArtistLibraryStatistics? stats,
    SonusCinematicColors colors,
  ) {
    final rank = stats?.rank;
    final known = widget.statisticsLoaded;
    return _StatItem(
      key: const ValueKey<String>('film-reel-rank'),
      icon: Icons.emoji_events_rounded,
      value: !known ? '–' : (rank == null ? 'Unranked' : '#$rank'),
      label: 'Rank',
      semanticsLabel: !known
          ? 'Rank loading'
          : (rank == null ? 'Unranked' : 'Ranked number $rank'),
      colors: colors,
    );
  }

  List<Widget> _rightStats(
    ArtistLibraryStatistics? stats,
    SonusCinematicColors colors,
  ) {
    final known = widget.statisticsLoaded;
    final streams = stats?.qualifiedStreams ?? 0;
    final listened = stats?.listened;
    final hasListened = listened != null && listened > Duration.zero;
    return [
      _StatItem(
        key: const ValueKey<String>('film-reel-streams'),
        icon: Icons.bar_chart_rounded,
        value: known ? '$streams' : '–',
        label: sonusCountNoun(streams, 'Stream'),
        semanticsLabel: known
            ? sonusCount(streams, 'stream')
            : 'Streams loading',
        colors: colors,
      ),
      _StatItem(
        key: const ValueKey<String>('film-reel-listened'),
        icon: Icons.schedule_rounded,
        value: known && hasListened ? sonusListeningTime(listened) : '–',
        label: 'Listened',
        semanticsLabel: !known
            ? 'Listening time loading'
            : hasListened
            ? '${sonusListeningTime(listened)} listened'
            : 'No listening time yet',
        colors: colors,
      ),
      _TopTrackItem(stats: stats, loaded: known, colors: colors),
    ];
  }

  Widget _reel(
    BuildContext context,
    SonusCinematicColors colors, {
    required double height,
    required double cardWidth,
    required double cardHeight,
  }) {
    const gap = 28.0;
    final fraction = ((cardHeight + gap) / height).clamp(0.3, 1.0);
    final pages = _controllerFor(fraction);
    final peek = (height - height * fraction) / 2;
    final many = widget.artists.length > 1;

    final reel = PageView.builder(
      key: const ValueKey<String>('film-reel-pages'),
      controller: pages,
      scrollDirection: Axis.vertical,
      itemCount: widget.artists.length,
      onPageChanged: _centre,
      itemBuilder: (context, index) {
        final artist = widget.artists[index];
        return AnimatedBuilder(
          animation: pages,
          builder: (context, child) {
            final page = pages.hasClients && pages.position.haveDimensions
                ? pages.page ?? _index.toDouble()
                : _index.toDouble();
            final distance = (page - index).abs().clamp(0.0, 1.0);
            return Opacity(
              opacity: 1 - distance * 0.55,
              child: Transform.scale(scale: 1 - distance * 0.12, child: child),
            );
          },
          child: Center(
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _ReelCard(
                key: ValueKey<String>('artist-${artist.artistId}'),
                artist: artist,
                stats: widget.statistics[artist.artistId],
                statisticsLoaded: widget.statisticsLoaded,
                centred: index == _index,
                colors: colors,
                width: cardWidth,
                onTap: () => index == _index
                    ? widget.onOpenArtist(artist)
                    : _goTo(index),
              ),
            ),
          ),
        );
      },
    );

    final onRefresh = widget.onRefresh;
    return Stack(
      children: [
        Positioned.fill(
          child: onRefresh == null
              ? reel
              : RefreshIndicator(onRefresh: onRefresh, child: reel),
        ),
        if (many) ...[
          Positioned(
            top: (peek - 44).clamp(0.0, double.infinity),
            left: 0,
            right: 0,
            child: Center(
              child: _Chevron(
                key: const ValueKey<String>('film-reel-previous'),
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Previous artist',
                colors: colors,
                onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
              ),
            ),
          ),
          Positioned(
            bottom: (peek - 44).clamp(0.0, double.infinity),
            left: 0,
            right: 0,
            child: Center(
              child: _Chevron(
                key: const ValueKey<String>('film-reel-next'),
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Next artist',
                colors: colors,
                onPressed: _index < widget.artists.length - 1
                    ? () => _goTo(_index + 1)
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReelHeader extends StatelessWidget {
  const _ReelHeader({
    required this.countLabel,
    required this.colors,
    required this.onOpenRoster,
    required this.onOpenSearch,
  });

  final String countLabel;
  final SonusCinematicColors colors;
  final VoidCallback? onOpenRoster;
  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = SonusTheme.of(context).decoration;
    final enabled = onOpenRoster != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Library',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  countLabel,
                  key: const ValueKey<String>('library-artist-count'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onOpenSearch != null)
            IconButton(
              key: const ValueKey<String>('library-search-button'),
              tooltip: 'Search artists',
              onPressed: onOpenSearch,
              color: colors.textPrimary,
              icon: const Icon(Icons.search_rounded),
            ),
          const SizedBox(width: 4),
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.accent, width: 1.5),
                boxShadow: SonusGlow.shadows(
                  colors.glow,
                  decoration,
                  blurRadius: 14,
                ),
              ),
              child: IconButton(
                key: const ValueKey<String>('library-roster-button'),
                tooltip: 'Artist Roster',
                onPressed: onOpenRoster,
                color: colors.textPrimary,
                disabledColor: colors.textPrimary,
                icon: const Icon(Icons.sports_esports_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
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
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: colors.textPrimary,
      disabledColor: colors.textSecondary.withValues(alpha: 0.4),
      iconSize: 32,
      icon: Icon(icon),
    );
  }
}

class _ReelCard extends StatelessWidget {
  const _ReelCard({
    super.key,
    required this.artist,
    required this.stats,
    required this.statisticsLoaded,
    required this.centred,
    required this.colors,
    required this.width,
    required this.onTap,
  });

  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool statisticsLoaded;
  final bool centred;
  final SonusCinematicColors colors;
  final double width;
  final VoidCallback onTap;

  static const double radius = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = SonusTheme.of(context).decoration;
    final path = ArtistFilmReel.portraitPath(artist);
    final rank = stats?.rank;
    final standing = !statisticsLoaded
        ? ''
        : rank == null
        ? ' Unranked.'
        : ' Ranked number $rank.';

    return Semantics(
      button: true,
      label:
          '${artist.name}. ${sonusCount(artist.albumCount, 'release')}, '
          '${sonusCount(artist.songCount, 'song')}.$standing',
      hint: centred ? 'Opens the artist' : 'Shows this artist',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: centred ? colors.edge : colors.edge.withValues(alpha: 0.4),
            width: centred ? 2 : 1,
          ),
          boxShadow: centred
              ? SonusGlow.shadows(colors.glow, decoration)
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: Material(
            color: colors.surface,
            child: InkWell(
              key: ValueKey<String>('artist-open-${artist.artistId}'),
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (path == null)
                    _Initials(name: artist.name, colors: colors)
                  else
                    Image.file(
                      File(path),
                      key: ValueKey<String>(
                        'film-reel-portrait-${artist.artistId}',
                      ),
                      fit: BoxFit.cover,
                      // Square portraits fill the tall frame from the top,
                      // where faces usually are (D1).
                      alignment: const Alignment(0, -0.35),
                      // Decoded at the card's size, never at full
                      // resolution.
                      cacheWidth:
                          (width * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          _Initials(name: artist.name, colors: colors),
                    ),
                  // Keeps the name readable over any photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC000000)],
                        stops: [0.5, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 14,
                    child: Text(
                      artist.name,
                      key: ValueKey<String>(
                        'film-reel-name-${artist.artistId}',
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFFFFFFFF),
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.colors});

  final String name;
  final SonusCinematicColors colors;

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
      key: const ValueKey<String>('film-reel-initials'),
      color: colors.surface,
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              initials,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
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

/// A tilted glass panel beside the portrait.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    super.key,
    required this.angle,
    required this.hinge,
    required this.colors,
    required this.identity,
    required this.children,
  });

  final double angle;
  final Alignment hinge;
  final SonusCinematicColors colors;
  final Key identity;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SonusPerspectivePanel(
      angle: angle,
      alignment: hinge,
      child: SonusGlassPanel(
        base: colors.surface,
        edge: colors.edge,
        glow: colors.glow,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: _CrossFade(
          identity: identity,
          // Scales down rather than overflowing a narrow panel.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0) const SizedBox(height: 18),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The statistics under the reel, on narrow screens and with large text.
class _StatsArea extends StatelessWidget {
  const _StatsArea({
    super.key,
    required this.colors,
    required this.artist,
    required this.stats,
    required this.loaded,
    required this.identity,
    required this.width,
    required this.textScale,
  });

  final SonusCinematicColors colors;
  final LibraryArtist artist;
  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final Key identity;
  final double width;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_ArtistFilmReelState>()!;
    Widget panel(List<Widget> items, Key key) => SonusGlassPanel(
      key: key,
      base: colors.surface,
      edge: colors.edge,
      padding: const EdgeInsets.all(12),
      child: _CrossFade(
        identity: identity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              item,
            ],
          ],
        ),
      ),
    );

    final left = panel(
      state._leftStats(stats, colors),
      const ValueKey<String>('film-reel-panel-left'),
    );
    final right = panel(
      state._rightStats(stats, colors),
      const ValueKey<String>('film-reel-panel-right'),
    );
    if (width >= 340 && textScale < 1.6) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [left, const SizedBox(height: 12), right],
    );
  }
}

/// Fades between one artist's statistics and the next (instantly with
/// reduced motion).
class _CrossFade extends StatelessWidget {
  const _CrossFade({required this.identity, required this.child});

  final Key identity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final reduced =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : tokens.motion.baseShort,
      child: KeyedSubtree(key: identity, child: child),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.semanticsLabel,
    required this.colors,
  });

  final IconData icon;
  final String value;
  final String label;
  final String semanticsLabel;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopTrackItem extends StatelessWidget {
  const _TopTrackItem({
    required this.stats,
    required this.loaded,
    required this.colors,
  });

  final ArtistLibraryStatistics? stats;
  final bool loaded;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = stats?.topTrack;
    final title = top?.track.displayTitle;

    return Semantics(
      label: title == null
          ? (loaded ? 'No top track yet' : 'Top track loading')
          : 'Top track: $title',
      excludeSemantics: true,
      child: Column(
        key: const ValueKey<String>('film-reel-top-track'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (top != null)
            SonusArtworkImage(path: top.track.artworkPath, size: 52)
          else
            Icon(Icons.star_rounded, color: colors.accent, size: 24),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Text(
              title ?? '–',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
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
    );
  }
}
