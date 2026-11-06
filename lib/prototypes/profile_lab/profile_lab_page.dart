// Artist Profile Lab: an isolated rendering prototype of the Artist Profile.
//
// PROTOTYPE ONLY. Not reachable from app navigation and not imported by any
// production code; rendered by test/visual_lab/. It reads the Sonus theme
// tokens and the shared artwork services (SonusArtworkColorsRequest,
// SonusArtworkPalette, SonusArtworkImage) but owns its own composition:
// a fixed, lit artwork environment (LabBackdrop), glass plates (LabGlass),
// local grounds behind text on the backdrop, and a header that collapses
// into a glass toolbar. Buttons, tabs and menus are visual placeholders.
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design/sonus_artwork_palette.dart';
import '../../core/design/sonus_text_scale.dart';
import '../../core/design/sonus_theme.dart';
import '../../core/design/widgets/sonus_artwork_colors_request.dart';
import '../../core/design/widgets/playback/sonus_mini_player.dart';
import '../../core/design/widgets/sonus_artwork_image.dart';
import 'profile_lab_atmosphere.dart';
import 'profile_lab_backdrop.dart';
import 'profile_lab_glass.dart';
import 'profile_lab_models.dart';

/// Named sizes of the lab page, with their responsive rules.
abstract final class LabGeometry {
  /// The hero photo's height: about a third of the screen (the reference's
  /// proportion), shorter with large text so the controls stay above the
  /// player at the top of the page.
  static double heroPhotoHeight(Size screen, {double textScale = 1}) =>
      textScale > sonusLargeTextScale
      ? (screen.height * 0.22).clamp(170.0, 240.0)
      : (screen.height * 0.32).clamp(230.0, 330.0);

  /// How far the identity block rises into the photo.
  static const double identityOverlap = 92;

  /// The portrait: smaller on narrow phones and with large text.
  static double portraitSize(double width, {required bool largeText}) =>
      largeText ? 88 : (width < 400 ? 96 : 108);

  static const double gutter = 20;
  static const double controlHeight = 52;

  /// Track rows: compact, still a full 48dp touch target.
  static const double trackRowHeight = 56;
  static const double trackArtwork = 44;
  static const double releaseCover = 112;
  static const double toolbarHeight = 56;
  static const double sectionGap = 22;

  /// The mini-player's own sizes (the production bar's, read, not copied),
  /// so clearance here is what the integrated page will need.
  static double miniPlayerHeight(BuildContext context) =>
      SonusMiniPlayer.barHeight(context);
  static const double miniPlayerMargin = 8;

  /// Room left under the content so its end scrolls fully above the
  /// player and the navigation bar.
  static double bottomRoom(BuildContext context, {required bool player}) =>
      MediaQuery.paddingOf(context).bottom +
      (player ? miniPlayerHeight(context) + miniPlayerMargin * 2 : 0) +
      16;
}

class ProfileLabPage extends StatefulWidget {
  const ProfileLabPage({
    super.key,
    required this.profile,
    this.artworkPalette,
    this.layers = LabLayers.all,
    this.scrollController,
    this.showMiniPlayer = true,
  });

  final LabArtistProfile profile;

  /// Where artwork colours come from; the app-wide cache when null.
  final SonusArtworkPalette? artworkPalette;
  final LabLayers layers;
  final ScrollController? scrollController;

  /// The mini-player placeholder (the real one is the shell's).
  final bool showMiniPlayer;

  @override
  State<ProfileLabPage> createState() => _ProfileLabPageState();
}

class _ProfileLabPageState extends State<ProfileLabPage>
    with SonusArtworkColorsRequest<ProfileLabPage> {
  ScrollController? _ownController;
  int _tab = 0;

  ScrollController get _controller =>
      widget.scrollController ?? (_ownController ??= ScrollController());

  @override
  SonusArtworkPalette? get artworkPalette => widget.artworkPalette;

  @override
  ValueListenable<String?>? artworkPathListenableOf(ProfileLabPage widget) =>
      null;

  @override
  String? artworkPathOf(ProfileLabPage widget) => widget.profile.atmospherePath;

  @override
  void dispose() {
    _ownController?.dispose();
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
    final profile = widget.profile;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final largeText = media.textScaler.scale(1) > sonusLargeTextScale;
    final photoHeight = LabGeometry.heroPhotoHeight(
      screen,
      textScale: media.textScaler.scale(1),
    );
    final showPlayer = widget.showMiniPlayer && profile.nowPlaying != null;
    final bottomRoom = LabGeometry.bottomRoom(context, player: showPlayer);

    final content = CustomScrollView(
      key: const ValueKey<String>('lab-scroll'),
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            profile: profile,
            atmosphere: a,
            layers: layers,
            photoHeight: photoHeight,
            largeText: largeText,
          ),
        ),
        _padded(_Controls(atmosphere: a, layers: layers), top: 14),
        _padded(
          _Tabs(
            atmosphere: a,
            layers: layers,
            selected: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          top: 12,
        ),
        _padded(
          _SectionHeader(
            key: const ValueKey<String>('lab-top-tracks-header'),
            atmosphere: a,
            layers: layers,
            title: 'Top Tracks',
            subtitle: 'Your most streamed songs',
          ),
          top: LabGeometry.sectionGap,
        ),
        _padded(
          _TopTracks(tracks: profile.topTracks, atmosphere: a, layers: layers),
          top: 10,
        ),
        _padded(
          _SectionHeader(
            key: const ValueKey<String>('lab-releases-header'),
            atmosphere: a,
            layers: layers,
            title: 'Releases',
            trailing: '${profile.releases.length} releases',
          ),
          top: LabGeometry.sectionGap,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Releases(
              releases: profile.releases,
              atmosphere: a,
              layers: layers,
            ),
          ),
        ),
        _padded(
          _SectionHeader(
            key: const ValueKey<String>('lab-collaborations-header'),
            atmosphere: a,
            layers: layers,
            title: 'Collaborations',
            trailing: '${profile.collaborations.length} artists',
          ),
          top: LabGeometry.sectionGap,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Collaborations(
              artistPortrait: profile.portraitPath,
              collaborations: profile.collaborations,
              atmosphere: a,
              layers: layers,
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomRoom)),
      ],
    );

    return Scaffold(
      key: const ValueKey<String>('lab-page'),
      backgroundColor: a.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: LabBackdrop(
              artworkPath: profile.atmospherePath,
              atmosphere: a,
              layers: layers,
            ),
          ),
          Positioned.fill(child: content),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Toolbar(
              title: profile.name,
              controller: _controller,
              collapseAt: photoHeight - LabGeometry.toolbarHeight - 24,
              atmosphere: a,
              layers: layers,
            ),
          ),
          if (layers.scrims && a.effects)
            // Content leaving the screen fades into the deep tone under the
            // player and the navigation bar instead of showing through.
            Positioned(
              key: const ValueKey<String>('lab-scrim-bottom'),
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomRoom + 20,
              child: _Scrim.vertical(a.groundDeep, 0.9, fromTop: false),
            ),
          if (showPlayer)
            Positioned(
              left: LabGeometry.miniPlayerMargin,
              right: LabGeometry.miniPlayerMargin,
              bottom: media.padding.bottom + LabGeometry.miniPlayerMargin,
              child: _MiniPlayerPlaceholder(
                track: profile.nowPlaying!,
                artistName: profile.name,
                atmosphere: a,
                layers: layers,
              ),
            ),
        ],
      ),
    );
  }

  static Widget _padded(Widget child, {double top = 0}) => SliverPadding(
    padding: EdgeInsets.fromLTRB(
      LabGeometry.gutter,
      top,
      LabGeometry.gutter,
      0,
    ),
    sliver: SliverToBoxAdapter(child: child),
  );
}

// ------------------------------------------------------------------ hero

class _Hero extends StatelessWidget {
  const _Hero({
    required this.profile,
    required this.atmosphere,
    required this.layers,
    required this.photoHeight,
    required this.largeText,
  });

  final LabArtistProfile profile;
  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final double photoHeight;
  final bool largeText;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final portrait = LabGeometry.portraitSize(width, largeText: largeText);
    final photo = profile.bannerPath ?? profile.portraitPath;
    final theme = Theme.of(context);
    final textShadow = a.effects
        ? [
            Shadow(
              color: a.groundDeep.withValues(alpha: a.textPrimary.a * 0.7),
              blurRadius: 18,
            ),
          ]
        : null;

    final name = Text(
      profile.name,
      key: const ValueKey<String>('lab-name'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.headlineMedium?.copyWith(
        color: a.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 28,
        height: 1.08,
        letterSpacing: -0.4,
        shadows: textShadow,
      ),
    );

    final details = Column(
      crossAxisAlignment: largeText
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        name,
        if (profile.standing case final standing?) ...[
          const SizedBox(height: 6),
          LabGlass(
            key: const ValueKey<String>('lab-standing'),
            atmosphere: a,
            layers: layers,
            radius: 999,
            raised: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              standing,
              style: theme.textTheme.labelLarge?.copyWith(
                color: a.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _StatsPlate(
          atmosphere: a,
          layers: layers,
          stats: [
            _StatChip(
              key: const ValueKey<String>('lab-stat-streams'),
              icon: Icons.headphones_rounded,
              value: '${profile.streams}',
              label: 'Streams',
              atmosphere: a,
            ),
            _StatChip(
              key: const ValueKey<String>('lab-stat-listened'),
              icon: Icons.schedule_rounded,
              value: _duration(profile.listened),
              label: 'Listened',
              atmosphere: a,
            ),
          ],
        ),
      ],
    );

    final portraitWidget = _Portrait(
      path: layers.heroPhoto ? profile.portraitPath : null,
      size: portrait,
      atmosphere: a,
    );

    final identity = largeText
        ? Column(
            children: [portraitWidget, const SizedBox(height: 10), details],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              portraitWidget,
              const SizedBox(width: 14),
              Expanded(child: details),
            ],
          );

    return Stack(
      // The identity scrim runs past the block's bottom; clipping it here
      // would leave a hard line across the page.
      clipBehavior: Clip.none,
      children: [
        Positioned(
          key: const ValueKey<String>('lab-hero-photo'),
          top: 0,
          left: 0,
          right: 0,
          height: photoHeight,
          child: ExcludeSemantics(
            child: layers.heroPhoto && photo != null
                ? ShaderMask(
                    // Full strength over most of the photo; a short fade
                    // into the page at the bottom.
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                      stops: [0.6, 1],
                    ).createShader(rect),
                    child: Image.file(
                      File(photo),
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.35),
                      cacheWidth: (width * media.devicePixelRatio).round(),
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (layers.scrims) ...[
          // Under the status bar and toolbar icons only.
          Positioned(
            key: const ValueKey<String>('lab-scrim-top'),
            top: 0,
            left: 0,
            right: 0,
            height: media.padding.top + 88,
            child: _Scrim.vertical(a.groundDeep, 0.55, fromTop: true),
          ),
          // Under the identity block: the photo darkens only where the
          // name and chips sit.
          Positioned(
            key: const ValueKey<String>('lab-scrim-identity'),
            top: photoHeight - LabGeometry.identityOverlap - 60,
            left: 0,
            right: 0,
            height: LabGeometry.identityOverlap + 120,
            child: _Scrim.band(a.ground, 0.62),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(
            LabGeometry.gutter,
            photoHeight - LabGeometry.identityOverlap,
            LabGeometry.gutter,
            0,
          ),
          child: identity,
        ),
      ],
    );
  }
}

String _duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

class _Scrim extends StatelessWidget {
  const _Scrim.vertical(this.colour, this.alpha, {required this.fromTop})
    : band = false;
  const _Scrim.band(this.colour, this.alpha) : band = true, fromTop = false;

  final Color colour;
  final double alpha;
  final bool fromTop;
  final bool band;

  @override
  Widget build(BuildContext context) {
    final c = colour.withValues(alpha: alpha);
    final clear = colour.withValues(alpha: 0);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: band
                ? [
                    clear,
                    c.withValues(alpha: alpha * 0.6),
                    c,
                    c.withValues(alpha: alpha * 0.45),
                    clear,
                  ]
                : fromTop
                ? [c, clear]
                : [clear, c],
            stops: band ? const [0, 0.22, 0.48, 0.74, 1] : null,
          ),
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
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
    return Container(
      key: const ValueKey<String>('lab-portrait'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A lit ring rather than a flat outline.
        gradient: a.effects
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFFFFF).withValues(alpha: 0.75),
                  a.light.withValues(alpha: 0.55),
                  a.groundDeep.withValues(alpha: 0.4),
                ],
              )
            : null,
        color: a.effects ? null : a.glassRim,
        boxShadow: a.effects
            ? [
                BoxShadow(
                  color: a.light.withValues(alpha: 0.35),
                  blurRadius: 26,
                ),
              ]
            : null,
      ),
      child: Semantics(
        image: true,
        label: 'Artist photo',
        child: ClipOval(
          child: SonusArtworkImage(
            path: path,
            size: size - 6,
            circular: true,
            placeholderIcon: Icons.person_rounded,
          ),
        ),
      ),
    );
  }
}

/// The listening statistics on one glass plate, side by side with a
/// divider; stacked when there is no room (narrow phones, large text).
class _StatsPlate extends StatelessWidget {
  const _StatsPlate({
    required this.atmosphere,
    required this.layers,
    required this.stats,
  });

  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 200 * scale;
        return LabGlass(
          key: const ValueKey<String>('lab-stats'),
          atmosphere: a,
          layers: layers,
          radius: 16,
          raised: false,
          quiet: true,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: sideBySide
              ? IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      stats[0],
                      VerticalDivider(
                        width: 17,
                        thickness: 1,
                        indent: 4,
                        endIndent: 4,
                        color: a.border,
                      ),
                      stats[1],
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [stats[0], const SizedBox(height: 6), stats[1]],
                ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.atmosphere,
  });

  final IconData icon;
  final String value;
  final String label;
  final LabAtmosphere atmosphere;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$value $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: a.textSecondary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: text.titleSmall?.copyWith(
                  color: a.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                label,
                style: text.labelSmall?.copyWith(color: a.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- controls

class _Controls extends StatelessWidget {
  const _Controls({required this.atmosphere, required this.layers});

  final LabAtmosphere atmosphere;
  final LabLayers layers;

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

    return Row(
      key: const ValueKey<String>('lab-controls'),
      children: [
        round(Icons.shuffle_rounded, 'Shuffle', 'lab-shuffle'),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Play all',
            excludeSemantics: true,
            child: Container(
              key: const ValueKey<String>('lab-play'),
              constraints: const BoxConstraints(
                minHeight: LabGeometry.controlHeight,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [a.accentTop, a.accentBottom],
                ),
                border: a.effects
                    ? Border.all(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.22),
                      )
                    : null,
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: a.onAccent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Play all',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              color: a.onAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        round(Icons.favorite_border_rounded, 'Favourite', 'lab-favourite'),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.atmosphere,
    required this.layers,
    required this.selected,
    required this.onSelected,
  });

  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final int selected;
  final ValueChanged<int> onSelected;

  static const labels = ['Overview', 'Releases', 'Collaborations'];

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    // With large text the labels keep their full width and the row scrolls
    // sideways, rather than truncating to "Over…".
    final large =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;
    Widget tab(int i) => Semantics(
      button: true,
      selected: i == selected,
      label: labels[i],
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => onSelected(i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: large ? 14 : 6),
          decoration: i == selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [a.accentTop, a.accentBottom],
                  ),
                )
              : null,
          child: Text(
            labels[i],
            maxLines: 1,
            overflow: large ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: false,
            style: text.labelLarge?.copyWith(
              color: i == selected ? a.onAccent : a.textPrimary,
              fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    return LabGlass(
      key: const ValueKey<String>('lab-tabs'),
      atmosphere: a,
      layers: layers,
      radius: 26,
      raised: false,
      quiet: true,
      padding: const EdgeInsets.all(4),
      child: large
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [for (var i = 0; i < labels.length; i++) tab(i)],
              ),
            )
          : Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(flex: i == 2 ? 13 : 10, child: tab(i)),
              ],
            ),
    );
  }
}

// -------------------------------------------------------------- sections

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.atmosphere,
    required this.layers,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final LabAtmosphere atmosphere;
  final LabLayers layers;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    final large =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;
    final count = trailing == null
        ? null
        : Text(
            trailing!,
            style: text.labelLarge?.copyWith(color: a.textSecondary),
          );
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: a.accentLine,
                borderRadius: BorderRadius.circular(2),
                boxShadow: a.effects
                    ? [
                        BoxShadow(
                          color: a.accentLine.withValues(alpha: 0.6),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.titleLarge?.copyWith(
                    color: a.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (count != null && !large) count,
          ],
        ),
        // With large text the count gets its own line, so the title never
        // breaks inside a word ("Collaborat-ions").
        if (count != null && large) ...[const SizedBox(height: 2), count],
        if (subtitle case final subtitle?) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: text.bodyMedium?.copyWith(color: a.textSecondary),
          ),
        ],
      ],
    );
    if (!layers.scrims || !a.effects) return header;
    // A soft local ground: darkest under the words, gone at the edges.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -LabGeometry.gutter,
          right: -LabGeometry.gutter,
          top: -24,
          bottom: -24,
          child: IgnorePointer(
            // Faded on all four sides, so it never shows as a band.
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, 0.35, 0.65, 1],
              ).createShader(rect),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      a.groundDeep.withValues(alpha: 0.5),
                      a.groundDeep.withValues(alpha: 0.3),
                      a.groundDeep.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        header,
      ],
    );
  }
}

class _TopTracks extends StatelessWidget {
  const _TopTracks({
    required this.tracks,
    required this.atmosphere,
    required this.layers,
  });

  final List<LabTrack> tracks;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    return LabGlass(
      key: const ValueKey<String>('lab-top-tracks-card'),
      atmosphere: a,
      layers: layers,
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 84,
                endIndent: 16,
                // Hairlines, not rules: the rows read as one list.
                color: a.border.withValues(alpha: a.border.a * 0.6),
              ),
            _TrackRow(
              key: ValueKey<String>('lab-track-$i'),
              index: i,
              track: tracks[i],
              atmosphere: a,
              layers: layers,
            ),
          ],
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: a.border.withValues(alpha: a.border.a * 0.6),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Semantics(
              button: true,
              label: 'View all tracks',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey<String>('lab-view-all'),
                borderRadius: BorderRadius.circular(16),
                onTap: () {},
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View all tracks',
                        style: text.labelLarge?.copyWith(
                          color: a.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: a.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.atmosphere,
    required this.layers,
  });

  final int index;
  final LabTrack track;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    final playing = track.isPlaying;
    final large =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {},
          child: Container(
            constraints: const BoxConstraints(
              minHeight: LabGeometry.trackRowHeight,
            ),
            padding: const EdgeInsets.fromLTRB(8, 5, 0, 5),
            // The playing row is lit, not framed: a faint tint, no edge.
            decoration: playing
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: a.accentLine.withValues(alpha: 0.08),
                  )
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: playing
                      ? Icon(
                          Icons.graphic_eq_rounded,
                          size: 20,
                          color: a.layersInk(a.accentLine),
                          semanticLabel: 'Playing',
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: text.titleSmall?.copyWith(
                            color: a.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                SonusArtworkImage(
                  path: layers.thumbnails ? track.artworkPath : null,
                  size: LabGeometry.trackArtwork,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: a.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${track.streams} streams · ${track.releaseTitle}',
                        maxLines: large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: a.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'More for ${track.title}',
                  onPressed: () {},
                  icon: Icon(Icons.more_vert_rounded, color: a.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on LabAtmosphere {
  /// [colour], or transparent when the ink layer is off.
  Color layersInk(Color colour) =>
      textPrimary.a == 0 ? const Color(0x00000000) : colour;
}

class _Releases extends StatelessWidget {
  const _Releases({
    required this.releases,
    required this.atmosphere,
    required this.layers,
  });

  final List<LabRelease> releases;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Wider cards with large text so titles wrap between words.
    final cardWidth = (LabGeometry.releaseCover * (1 + (scale - 1) * 0.5))
        .clamp(LabGeometry.releaseCover, 170.0);
    return SizedBox(
      key: const ValueKey<String>('lab-releases'),
      height: cardWidth + 12 + 62 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LabGeometry.gutter),
        itemCount: releases.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final release = releases[i];
          return SizedBox(
            key: ValueKey<String>('lab-release-$i'),
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: a.effects
                        ? [
                            BoxShadow(
                              color: a.groundDeep.withValues(alpha: 0.6),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: SonusArtworkImage(
                    path: layers.thumbnails ? release.artworkPath : null,
                    size: cardWidth,
                    semanticLabel: 'Cover of ${release.title}',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  release.edition == null
                      ? release.title
                      : '${release.title} (${release.edition})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: a.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${release.year}',
                  style: text.bodySmall?.copyWith(color: a.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Collaborations extends StatelessWidget {
  const _Collaborations({
    required this.artistPortrait,
    required this.collaborations,
    required this.atmosphere,
    required this.layers,
  });

  final String? artistPortrait;
  final List<LabCollaboration> collaborations;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      key: const ValueKey<String>('lab-collaborations'),
      height: 52 + 46 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: LabGeometry.gutter),
        itemCount: collaborations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = collaborations[i];
          return SizedBox(
            key: ValueKey<String>('lab-collaboration-$i'),
            width: 232,
            child: LabGlass(
              atmosphere: a,
              layers: layers,
              radius: 22,
              raised: false,
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 44,
                    child: Stack(
                      children: [
                        SonusArtworkImage(
                          path: layers.thumbnails ? artistPortrait : null,
                          size: 44,
                          circular: true,
                          placeholderIcon: Icons.person_rounded,
                        ),
                        Positioned(
                          left: 28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: a.ground, width: 2),
                            ),
                            child: SonusArtworkImage(
                              path: layers.thumbnails
                                  ? c.partnerPortraitPath
                                  : null,
                              size: 44,
                              circular: true,
                              placeholderIcon: Icons.person_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'with ${c.partnerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            color: a.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${c.songCount} songs together',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: a.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------- toolbar, player

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.title,
    required this.controller,
    required this.collapseAt,
    required this.atmosphere,
    required this.layers,
  });

  final String title;
  final ScrollController controller;

  /// Scroll offset at which the toolbar starts turning to glass.
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
          key: const ValueKey<String>('lab-toolbar'),
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
              _ToolbarButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                plate: 1 - t,
                atmosphere: a,
                layers: layers,
              ),
              Expanded(
                child: AnimatedOpacity(
                  key: const ValueKey<String>('lab-toolbar-title'),
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
              _ToolbarButton(
                icon: Icons.more_vert_rounded,
                label: 'More',
                plate: 1 - t,
                atmosphere: a,
                layers: layers,
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
        if (!a.effects || t == 0) return bar;
        // Glass once collapsed: the content scrolling under it is blurred.
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

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.plate,
    required this.atmosphere,
    required this.layers,
  });

  final IconData icon;
  final String label;

  /// How much of the round plate shows (1 over the photo, 0 collapsed).
  final double plate;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    return IconButton(
      tooltip: label,
      onPressed: () {},
      style: IconButton.styleFrom(
        // A round plate while the button sits on the photo; solid in the
        // flat modes, which draw no scrim behind it.
        backgroundColor: layers.glass
            ? (a.effects ? a.groundDeep : a.ground).withValues(
                alpha: (a.effects ? 0.38 : 0.8) * plate,
              )
            : null,
      ),
      icon: Icon(icon, color: a.textPrimary),
    );
  }
}

class _MiniPlayerPlaceholder extends StatelessWidget {
  const _MiniPlayerPlaceholder({
    required this.track,
    required this.artistName,
    required this.atmosphere,
    required this.layers,
  });

  final LabTrack track;
  final String artistName;
  final LabAtmosphere atmosphere;
  final LabLayers layers;

  @override
  Widget build(BuildContext context) {
    final a = atmosphere;
    final text = Theme.of(context).textTheme;
    // Content scrolls under the player: a dense plate over a blur, not the
    // see-through card glass.
    final plate = a.effects
        ? LabGlass(
            atmosphere: _denser(a),
            layers: layers,
            radius: 22,
            child: const SizedBox.expand(),
          )
        : LabGlass(
            atmosphere: a,
            layers: layers,
            radius: 22,
            child: const SizedBox.expand(),
          );
    final body = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: LabGeometry.miniPlayerHeight(context),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          SonusArtworkImage(
            path: layers.thumbnails ? track.artworkPath : null,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: a.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: a.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Previous',
            onPressed: () {},
            icon: Icon(Icons.skip_previous_rounded, color: a.textPrimary),
          ),
          IconButton(
            tooltip: 'Pause',
            onPressed: () {},
            icon: Icon(
              Icons.pause_rounded,
              color: a.layersInk(a.accentLine),
              size: 30,
            ),
          ),
          IconButton(
            tooltip: 'Next',
            onPressed: () {},
            icon: Icon(Icons.skip_next_rounded, color: a.textPrimary),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
    final player = Stack(
      key: const ValueKey<String>('lab-mini-player'),
      children: [
        Positioned.fill(
          child: a.effects
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: plate,
                  ),
                )
              : plate,
        ),
        body,
      ],
    );
    return player;
  }

  static LabAtmosphere _denser(LabAtmosphere a) => LabAtmosphere(
    effects: a.effects,
    highContrast: a.highContrast,
    neutral: a.neutral,
    ground: a.ground,
    groundDeep: a.groundDeep,
    light: a.light,
    lightSecondary: a.lightSecondary,
    glass: Color.alphaBlend(a.glass, a.ground).withValues(alpha: 0.9),
    glassRim: a.glassRim,
    accentTop: a.accentTop,
    accentBottom: a.accentBottom,
    onAccent: a.onAccent,
    accentLine: a.accentLine,
    textPrimary: a.textPrimary,
    textSecondary: a.textSecondary,
    border: a.border,
  );
}
