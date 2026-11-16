import 'package:flutter/material.dart';

import '../../../../core/design/sonus_greyscale_theme.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../domain/entities/chart_entry.dart';
import '../models/chart_entry_movement.dart';
import '../models/chart_entry_text.dart';
import 'chart_movement_indicator.dart';
import 'chart_row_expansion.dart';
import 'chart_version_badge.dart';

/// The accent of a row's tile on a chart board (Charts 2.0 C3); one size
/// for every tier since App Update 1.3 Chart Studio.
enum ChartRowTier {
  /// #1 on the Top 100 board.
  featured,

  /// #2–10 on the Top 100 board.
  topTen,

  /// #11–100, and every Bubbling Under position.
  compact;

  static ChartRowTier of(ChartEntry entry) => entry.rank == 1
      ? ChartRowTier.featured
      : entry.rank <= 10
      ? ChartRowTier.topTen
      : ChartRowTier.compact;
}

/// Every position: one tile of the same size, #1 to #200 (App Update 1.3
/// Chart Studio): rank, genuine artwork, title and artist, and the movement.
/// Expanding opens the entry's statistics underneath, inside the same tile,
/// and outlines the tile in the theme's signature gradient. #1 adds a
/// trophy and #2–10 a tinted outline, never a larger card.
class ChartCompactRow extends StatefulWidget {
  const ChartCompactRow({
    super.key,
    required this.entry,
    required this.movement,
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    required this.fallbackIcon,
    required this.details,
    this.status,
    this.onTap,
    this.onLongPress,
    this.tier = ChartRowTier.compact,
    this.versionBadge,
  });

  final ChartEntry entry;
  final ChartEntryMovement movement;

  /// The accent of the tile's outline.
  final ChartRowTier tier;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final IconData fallbackIcon;
  final ChartEntryStatus? status;

  /// The entry's statistics, built only while expanded.
  final WidgetBuilder details;

  /// Opens the song (Song Stats in C4).
  final VoidCallback? onTap;

  /// Charts 2.0 C4: the song's playback actions.
  final VoidCallback? onLongPress;

  /// The song's version beside a recorded title (a finalized week), App
  /// Update 1.3 (REF-1.3-01); null for none.
  final String? versionBadge;

  @override
  State<ChartCompactRow> createState() => _ChartCompactRowState();
}

class _ChartCompactRowState extends State<ChartCompactRow>
    with SingleTickerProviderStateMixin {
  ValueNotifier<String?>? _shared;
  bool _open = false;
  AnimationController? _reveal;

  String get _id => widget.entry.entity.entityId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shared = ChartRowExpansion.maybeOf(context)?.open;
    if (shared == _shared) return;
    _shared?.removeListener(_sharedChanged);
    _shared = shared?..addListener(_sharedChanged);
    if (shared != null) _open = shared.value == _id;
    _revealController().value = _open ? 1 : 0;
  }

  @override
  void didUpdateWidget(ChartCompactRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shared = _shared;
    if (shared != null && oldWidget.entry.entity.entityId != _id) {
      _open = shared.value == _id;
      _revealController().value = _open ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _shared?.removeListener(_sharedChanged);
    _reveal?.dispose();
    super.dispose();
  }

  AnimationController _revealController() =>
      _reveal ??= AnimationController(vsync: this)
        ..addStatusListener((status) {
          // Drop the statistics once fully collapsed.
          if (status == AnimationStatus.dismissed && mounted) setState(() {});
        });

  void _sharedChanged() {
    final value = _shared!.value;
    final open = value == _id;
    if (open == _open) return;
    // Closed because another row opened: at once, so the row that opened
    // stays where it was on screen (see [_toggle]).
    _show(open, instant: !open && value != null);
  }

  void _show(bool open, {required bool instant}) {
    final motion = SonusTheme.of(context).motion;
    final reveal = _revealController();
    setState(() => _open = open);
    if (instant || motion.reduced) {
      reveal.value = open ? 1 : 0;
    } else {
      reveal.duration = motion.medium;
      open ? reveal.forward() : reveal.reverse();
    }
  }

  void _toggle() {
    final shared = _shared;
    if (shared == null) {
      _show(!_open, instant: false);
      return;
    }
    if (_open) {
      shared.value = null;
      return;
    }
    // Another row above may close as this one opens: keep this row where
    // it is on screen instead of letting the list jump.
    final before = _top();
    shared.value = _id;
    if (before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position = Scrollable.maybeOf(context)?.position;
      final after = _top();
      if (position == null || after == null) return;
      final shift = after - before;
      if (shift.abs() < 0.5) return;
      position.jumpTo(
        (position.pixels + shift).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  double? _top() {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final entry = widget.entry;
    final id = entry.entity.entityId;
    final status = switch (widget.status) {
      ChartEntryStatus.blacklisted => 'BLACKLISTED',
      ChartEntryStatus.unavailable => 'UNAVAILABLE',
      ChartEntryStatus.historical => 'HISTORICAL',
      null => null,
    };

    final row = Semantics(
      button: widget.onTap != null,
      label: [
        'Number ${entry.rank}',
        widget.title,
        if (widget.versionBadge case final version?) 'version $version',
        widget.subtitle,
        widget.movement.spokenLabel(entry.rank),
        ?status?.toLowerCase(),
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('charts-row-$id'),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 0, 8),
            child: Builder(
              builder: (context) {
                final scaler = MediaQuery.textScalerOf(context);
                // The rank keeps up to three digits at any text size,
                // without taking the title's room; the arrow sits under it.
                final rankWidth = scaler.scale(40).clamp(40.0, 60.0);
                final hasAchievement =
                    widget.movement.achievement != ChartAchievement.none;

                final rank = SizedBox(
                  width: rankWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // #1's trophy sits beside the rank, never above it,
                      // so #1 is the same height as every other row.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.tier == ChartRowTier.featured)
                              Icon(
                                Icons.emoji_events_rounded,
                                key: const ValueKey<String>(
                                  'charts-number-one',
                                ),
                                size: 14,
                                color:
                                    sonusThemeIsGreyscale(colors.accentPrimary)
                                    ? colors.textPrimary
                                    : colors.accentPrimary,
                              ),
                            Text(
                              '${entry.rank}',
                              key: ValueKey<String>('charts-rank-$id'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: entry.isOffChartStanding
                                    ? colors.textSecondary
                                    : colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ChartMovementIndicator(
                          entry: entry,
                          movement: widget.movement,
                          part: ChartIndicatorPart.arrow,
                        ),
                      ),
                    ],
                  ),
                );
                final titleText = Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                );
                final version = widget.versionBadge;
                final Widget title = version == null
                    ? titleText
                    : Row(
                        children: [
                          Flexible(child: titleText),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: ChartVersionBadge(
                              key: ValueKey<String>('charts-version-$id'),
                              label: version,
                            ),
                          ),
                        ],
                      );
                final subtitle = Text(
                  status == null
                      ? widget.subtitle
                      : '$status · ${widget.subtitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                );

                return Row(
                  children: [
                    rank,
                    const SizedBox(width: 8),
                    SonusArtworkImage(
                      path: widget.artworkPath,
                      size: 48,
                      placeholderIcon: widget.fallbackIcon,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (hasAchievement) ...[
                                // Scales down rather than overflow at
                                // large text.
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: ChartMovementIndicator(
                                      entry: entry,
                                      movement: widget.movement,
                                      part: ChartIndicatorPart.achievement,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(child: subtitle),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final open = _open;
    final reveal = _revealController();
    final showDetails = open || reveal.value > 0;
    final style = _TileStyle.of(tokens, widget.tier, selected: open);

    final toggle = Semantics(
      expanded: open,
      child: IconButton(
        key: ValueKey<String>(
          open ? 'charts-row-collapse-$id' : 'charts-row-expand-$id',
        ),
        tooltip: open ? 'Hide details' : 'Show details',
        onPressed: _toggle,
        icon: AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: tokens.motion.short,
          child: Icon(
            Icons.expand_more_rounded,
            color: open ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );

    return Container(
      key: ValueKey<String>('charts-tile-$id'),
      padding: const EdgeInsets.all(_TileStyle.outlineWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          tokens.metrics.cardRadius + _TileStyle.outlineWidth,
        ),
        gradient: style.outlineGradient,
        color: style.outlineGradient == null ? style.outline : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.background,
            gradient: style.backgroundGradient,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: row),
                    toggle,
                  ],
                ),
                if (showDetails)
                  SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: reveal,
                      curve: tokens.motion.curve,
                    ),
                    alignment: Alignment.topCenter,
                    child: Builder(builder: widget.details),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tile's outline and fill. Every tile has the same outline width, so
/// selection and the Top 10 accents never change a row's size. Without
/// gradients (High contrast, Low effects, Decoration Off) and in Monochrome
/// the outline is a plain colour.
class _TileStyle {
  const _TileStyle({
    required this.outline,
    required this.background,
    this.outlineGradient,
    this.backgroundGradient,
  });

  static const double outlineWidth = 1.5;

  factory _TileStyle.of(
    SonusThemeData tokens,
    ChartRowTier tier, {
    required bool selected,
  }) {
    final colors = tokens.colors;
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final gradients = tokens.decoration.allowGradients && !grey;
    final a = colors.accentPrimary;
    final b = colors.accentSecondary;
    Color over(Color tint, double alpha) =>
        Color.alphaBlend(tint.withValues(alpha: alpha), colors.surface);

    if (selected) {
      return _TileStyle(
        outline: grey ? colors.textPrimary : colors.focus,
        outlineGradient: gradients
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [a, b],
              )
            : null,
        background: over(colors.textPrimary, 0.04),
        backgroundGradient: gradients
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [over(a, 0.14), over(b, 0.05), over(b, 0.12)],
              )
            : null,
      );
    }
    return _TileStyle(
      outline: switch (tier) {
        _ when grey || tokens.decoration.highContrast => colors.border,
        ChartRowTier.featured => over(a, 0.55),
        ChartRowTier.topTen => over(a, 0.3),
        ChartRowTier.compact => Color.alphaBlend(
          colors.border.withValues(alpha: 0.6),
          colors.surface,
        ),
      },
      background: colors.surface,
    );
  }

  final Color outline;
  final Gradient? outlineGradient;
  final Color background;
  final Gradient? backgroundGradient;
}
