// Album Profile Lab: the Album Profile in the Profile Lab's visual
// architecture (artwork environment, frosted glass, local grounds).
//
// PROTOTYPE ONLY. Not reachable from app navigation and not imported by
// production code; rendered by test/visual_lab/. Editions switch the
// cover, the atmosphere and the track list; the header collapses into a
// glass toolbar. Buttons and menus are visual placeholders.
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design/sonus_artwork_palette.dart';
import '../../core/design/sonus_profile_effects.dart';
import '../../core/design/sonus_text_scale.dart';
import '../../core/design/sonus_theme.dart';
import '../../core/design/widgets/sonus_artwork_colors_request.dart';
import '../../core/design/widgets/sonus_artwork_image.dart';
import 'profile_lab_atmosphere.dart';
import 'profile_lab_backdrop.dart';
import 'profile_lab_glass.dart';
import 'profile_lab_page.dart' show LabGeometry;

/// One track of an edition.
@immutable
class LabAlbumTrack {
  const LabAlbumTrack(this.title, this.duration, {this.isPlaying = false});

  final String title;
  final Duration duration;
  final bool isPlaying;
}

/// One edition of the release (Standard, Deluxe…).
@immutable
class LabEdition {
  const LabEdition({required this.name, required this.tracks, this.coverPath});

  final String name;
  final String? coverPath;
  final List<LabAlbumTrack> tracks;
}

/// Everything the album lab page shows (illustrative content only).
@immutable
class LabAlbum {
  const LabAlbum({
    required this.title,
    required this.artistName,
    required this.year,
    required this.genre,
    required this.editions,
  });

  final String title;
  final String artistName;
  final int year;
  final String genre;
  final List<LabEdition> editions;
}

class AlbumLabPage extends StatefulWidget {
  const AlbumLabPage({
    super.key,
    required this.album,
    this.initialEdition = 0,
    this.artworkPalette,
    this.layers = LabLayers.all,
    this.scrollController,
  });

  final LabAlbum album;
  final int initialEdition;
  final SonusArtworkPalette? artworkPalette;
  final LabLayers layers;
  final ScrollController? scrollController;

  @override
  State<AlbumLabPage> createState() => _AlbumLabPageState();
}

class _AlbumLabPageState extends State<AlbumLabPage>
    with SonusArtworkColorsRequest<AlbumLabPage> {
  late final ValueNotifier<String?> _cover = ValueNotifier<String?>(
    _edition.coverPath,
  );
  late int _editionIndex = widget.initialEdition;
  ScrollController? _own;

  LabEdition get _edition => widget.album.editions[_editionIndex];
  ScrollController get _controller =>
      widget.scrollController ?? (_own ??= ScrollController());

  @override
  SonusArtworkPalette? get artworkPalette => widget.artworkPalette;

  // The atmosphere follows the selected edition's cover.
  @override
  ValueListenable<String?>? artworkPathListenableOf(AlbumLabPage widget) =>
      _cover;

  @override
  String? artworkPathOf(AlbumLabPage widget) => null;

  void _select(int index) {
    if (index == _editionIndex) return;
    setState(() => _editionIndex = index);
    _cover.value = _edition.coverPath;
  }

  @override
  void dispose() {
    _own?.dispose();
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    requestArtworkColors(Brightness.dark);
    final tokens = SonusTheme.of(context);
    final resolved = LabAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: artworkColors,
    );
    final layers = widget.layers;
    final a = layers.ink ? resolved : resolved.withoutInk;
    final album = widget.album;
    final edition = _edition;
    final media = MediaQuery.of(context);
    final large = media.textScaler.scale(1) > sonusLargeTextScale;
    final text = Theme.of(context).textTheme;
    final width = media.size.width;
    // The cover leads: about 62% of the width, smaller with large text.
    final coverSize = (width * (large ? 0.46 : 0.62)).clamp(150.0, 280.0);
    final total = edition.tracks.fold(Duration.zero, (t, x) => t + x.duration);

    final header = Column(
      key: const ValueKey<String>('album-lab-header'),
      children: [
        SizedBox(height: media.padding.top + LabGeometry.toolbarHeight + 4),
        _Cover(
          path: layers.heroPhoto ? edition.coverPath : null,
          size: coverSize,
          atmosphere: a,
        ),
        const SizedBox(height: 16),
        Text(
          album.title,
          key: const ValueKey<String>('album-lab-title'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.headlineMedium?.copyWith(
            color: a.textPrimary,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          album.artistName,
          style: text.titleMedium?.copyWith(
            color: a.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        LabGlass(
          key: const ValueKey<String>('album-lab-edition-pill'),
          atmosphere: a,
          layers: layers,
          radius: 999,
          raised: false,
          quiet: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Text(
            edition.name,
            style: text.labelLarge?.copyWith(
              color: a.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${edition.tracks.length} tracks · ${total.inMinutes} min',
          style: text.titleSmall?.copyWith(
            color: a.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${album.year} · ${album.genre}',
          style: text.bodyMedium?.copyWith(color: a.textSecondary),
        ),
      ],
    );

    final content = CustomScrollView(
      key: const ValueKey<String>('album-lab-scroll'),
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            LabGeometry.gutter,
            14,
            LabGeometry.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _Editions(
              editions: album.editions,
              selected: _editionIndex,
              onSelected: _select,
              atmosphere: a,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            LabGeometry.gutter,
            14,
            LabGeometry.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _AlbumControls(atmosphere: a, layers: layers, large: large),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            LabGeometry.gutter,
            18,
            LabGeometry.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _Tracks(
              key: ValueKey<String>('album-lab-tracks-${edition.name}'),
              tracks: edition.tracks,
              atmosphere: a,
              layers: layers,
              large: large,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: LabGeometry.bottomRoom(context, player: false) + 24,
          ),
        ),
      ],
    );

    return Scaffold(
      key: const ValueKey<String>('album-lab-page'),
      backgroundColor: a.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: LabBackdrop(
              artworkPath: layers.backdropImage ? edition.coverPath : null,
              atmosphere: a,
              layers: layers,
              restrained:
                  sonusProfileBackdropMode(tokens.decoration) ==
                  SonusProfileBackdropMode.restrained,
            ),
          ),
          Positioned.fill(child: content),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _AlbumToolbar(
              title: album.title,
              controller: _controller,
              collapseAt: coverSize * 0.7,
              atmosphere: a,
              layers: layers,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.path,
    required this.size,
    required this.atmosphere,
  });

  final String? path;
  final double size;
  final LabAtmosphere atmosphere;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    // A luminous rim and glow in the artwork's light, as in the reference.
    return Container(
      key: const ValueKey<String>('album-lab-cover'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: a.effects
            ? Border.all(color: a.light.withValues(alpha: 0.55), width: 1.5)
            : Border.all(color: a.glassRim),
        boxShadow: a.effects
            ? [
                BoxShadow(
                  color: a.light.withValues(alpha: 0.38),
                  blurRadius: 34,
                ),
                BoxShadow(
                  color: a.groundDeep.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.5),
        child: SonusArtworkImage(
          path: path,
          size: size,
          semanticLabel: 'Album cover',
        ),
      ),
    );
  }
}

/// Edition switch: a quiet segmented control; the selected edition is
/// marked by a check and weight as well as colour.
class _Editions extends StatelessWidget {
  const _Editions({
    required this.editions,
    required this.selected,
    required this.onSelected,
    required this.atmosphere,
  });

  final List<LabEdition> editions;
  final int selected;
  final ValueChanged<int> onSelected;
  final LabAtmosphere atmosphere;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey<String>('album-lab-editions'),
        scrollDirection: Axis.horizontal,
        child: LabGlass(
          atmosphere: a,
          radius: 999,
          raised: false,
          quiet: true,
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < editions.length; i++)
                Semantics(
                  button: true,
                  selected: i == selected,
                  label: '${editions[i].name} edition',
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey<String>('album-lab-edition-$i'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelected(i),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        minWidth: 96,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: i == selected
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: a.accentLine.withValues(alpha: 0.16),
                              border: Border.all(
                                color: a.accentLine.withValues(alpha: 0.45),
                              ),
                            )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i == selected) ...[
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: a.textPrimary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            editions[i].name,
                            style: text.titleSmall?.copyWith(
                              color: i == selected
                                  ? a.textPrimary
                                  : a.textSecondary,
                              fontWeight: i == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumControls extends StatelessWidget {
  const _AlbumControls({
    required this.atmosphere,
    required this.layers,
    required this.large,
  });

  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    Widget round(IconData icon, String label, String key) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        key: ValueKey<String>(key),
        dimension: LabGeometry.controlHeight,
        child: LabGlass(
          atmosphere: a,
          layers: layers,
          shape: BoxShape.circle,
          raised: false,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {},
              child: Center(child: Icon(icon, color: a.textPrimary)),
            ),
          ),
        ),
      ),
    );
    final play = Semantics(
      button: true,
      label: 'Play',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey<String>('album-lab-play'),
        constraints: const BoxConstraints(
          minHeight: LabGeometry.controlHeight,
          minWidth: 140,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [a.accentTop, a.accentBottom],
          ),
          boxShadow: a.effects
              ? [
                  BoxShadow(
                    color: a.accentTop.withValues(alpha: 0.42),
                    blurRadius: 30,
                    spreadRadius: -6,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: a.onAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Play',
                    style: text.titleMedium?.copyWith(
                      color: a.onAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final shuffle = round(
      Icons.shuffle_rounded,
      'Shuffle',
      'album-lab-shuffle',
    );
    final favourite = round(
      Icons.favorite_border_rounded,
      'Favourite',
      'album-lab-favourite',
    );
    return Wrap(
      key: const ValueKey<String>('album-lab-controls'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 10,
      children: large ? [play, shuffle, favourite] : [shuffle, play, favourite],
    );
  }
}

class _Tracks extends StatelessWidget {
  const _Tracks({
    super.key,
    required this.tracks,
    required this.atmosphere,
    required this.layers,
    required this.large,
  });

  final List<LabAlbumTrack> tracks;
  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    String time(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return LabGlass(
      key: const ValueKey<String>('album-lab-tracks-card'),
      atmosphere: a,
      layers: layers,
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: a.accentLine,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Tracks',
                      style: text.titleLarge?.copyWith(
                        color: a.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${tracks.length}',
                  style: text.labelLarge?.copyWith(color: a.textSecondary),
                ),
              ],
            ),
          ),
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 52,
                endIndent: 16,
                color: a.border.withValues(alpha: a.border.a * 0.6),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: InkWell(
                key: ValueKey<String>('album-lab-track-$i'),
                borderRadius: BorderRadius.circular(16),
                onTap: () {},
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: tracks[i].isPlaying
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: a.accentLine.withValues(alpha: 0.10),
                        )
                      : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: tracks[i].isPlaying
                            ? Icon(
                                Icons.graphic_eq_rounded,
                                size: 20,
                                color: a.textPrimary.a == 0
                                    ? const Color(0x00000000)
                                    : a.accentLine,
                                semanticLabel: 'Playing',
                              )
                            : Text(
                                '${i + 1}',
                                style: text.titleSmall?.copyWith(
                                  color: a.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tracks[i].title,
                          maxLines: large ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            color: a.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!large)
                        Text(
                          time(tracks[i].duration),
                          style: text.bodyMedium?.copyWith(
                            color: a.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      IconButton(
                        tooltip: 'More for ${tracks[i].title}',
                        onPressed: () {},
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: a.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumToolbar extends StatelessWidget {
  const _AlbumToolbar({
    required this.title,
    required this.controller,
    required this.collapseAt,
    required this.atmosphere,
    required this.layers,
  });

  final String title;
  final ScrollController controller;
  final double collapseAt;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final top = MediaQuery.paddingOf(context).top;
    final motion = SonusTheme.of(context).motion;
    final text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final offset = controller.hasClients ? controller.offset : 0.0;
        final t = ((offset - collapseAt) / 64).clamp(0.0, 1.0);
        final bar = Container(
          key: const ValueKey<String>('album-lab-toolbar'),
          height: top + LabGeometry.toolbarHeight,
          padding: EdgeInsets.only(top: top),
          decoration: BoxDecoration(
            color: a.ground.withValues(alpha: (a.effects ? 0.72 : 1.0) * t),
            border: Border(
              bottom: BorderSide(
                color: a.border.withValues(alpha: a.border.a * t),
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Back',
                onPressed: () {},
                icon: Icon(Icons.arrow_back_rounded, color: a.textPrimary),
              ),
              Expanded(
                child: AnimatedOpacity(
                  key: const ValueKey<String>('album-lab-toolbar-title'),
                  opacity: t > 0.6 ? 1 : 0,
                  duration: motion.short,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                      color: a.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'More',
                onPressed: () {},
                icon: Icon(Icons.more_vert_rounded, color: a.textPrimary),
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
        if (!a.effects || t == 0) return bar;
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
            child: bar,
          ),
        );
      },
    );
  }
}
