import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_greyscale_theme.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_colors_request.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../domain/entities/chart_entry.dart';
import '../models/chart_entry_movement.dart';
import 'chart_entry_card.dart';
import 'chart_movement_indicator.dart';

/// How a row is presented on a chart board (Charts 2.0 C3).
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

/// #1: a slim frame in the theme's own gradient around the compact row,
/// over a tint of it; the row shows a trophy beside the rank. Plain under
/// high contrast, low effects and Decoration Off; greyscale in Monochrome.
class ChartFeaturedFrame extends StatelessWidget {
  const ChartFeaturedFrame({
    super.key,
    required this.chartName,
    required this.child,
  });

  final String chartName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients;
    final a = grey ? colors.textSecondary : colors.accentPrimary;
    final b = grey ? colors.textPrimary : colors.accentSecondary;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius + 2);

    return Semantics(
      container: true,
      label: 'No. 1 · $chartName',
      child: Container(
        key: const ValueKey<String>('charts-featured-frame'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: gradient
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [a, b],
                )
              : null,
          color: gradient ? null : colors.focus,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              gradient: gradient
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color.alphaBlend(
                          a.withValues(alpha: 0.24),
                          colors.surface,
                        ),
                        Color.alphaBlend(
                          b.withValues(alpha: 0.08),
                          colors.surface,
                        ),
                      ],
                    )
                  : null,
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// #2–10: the compact row in a slim frame with an accent from its own
/// artwork (theme colours when the artwork has none), over a light tint of
/// it. Monochrome uses no tint.
class ChartTopTenFrame extends StatefulWidget {
  const ChartTopTenFrame({
    super.key,
    required this.artworkPath,
    required this.child,
    this.palette,
  });

  final String? artworkPath;
  final Widget child;
  final SonusArtworkPalette? palette;

  @override
  State<ChartTopTenFrame> createState() => _ChartTopTenFrameState();
}

class _ChartTopTenFrameState extends State<ChartTopTenFrame>
    with SonusArtworkColorsRequest<ChartTopTenFrame> {
  @override
  SonusArtworkPalette? get artworkPalette => widget.palette;

  @override
  ValueListenable<String?>? artworkPathListenableOf(ChartTopTenFrame widget) =>
      null;

  @override
  String? artworkPathOf(ChartTopTenFrame widget) => widget.artworkPath;

  @override
  Widget build(BuildContext context) {
    // Re-requested when the artwork or the theme's brightness changes.
    requestArtworkColors(Theme.of(context).brightness);
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = sonusThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients && !grey;
    final accent = grey
        ? colors.border
        : artworkColors?.accent ?? colors.accentPrimary;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius + 1.5);
    final tint = grey || !tokens.decoration.allowGradients
        ? colors.surface
        : Color.alphaBlend(accent.withValues(alpha: 0.1), colors.surface);
    return Container(
      key: const ValueKey<String>('charts-top-ten-frame'),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient
            ? LinearGradient(colors: [accent, colors.accentSecondary])
            : null,
        color: gradient ? null : colors.border,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        child: Material(color: tint, child: widget.child),
      ),
    );
  }
}

/// Every position: one line — rank, genuine artwork, title and artist,
/// and the C2 movement — with the entry's full card one tap away. #1–10
/// are the same row inside a frame ([tier]); #1 adds a trophy.
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
  });

  final ChartEntry entry;
  final ChartEntryMovement movement;

  /// The frame around the row; a framed row has no divider of its own.
  final ChartRowTier tier;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final IconData fallbackIcon;
  final ChartEntryStatus? status;

  /// The entry's full card, shown when expanded.
  final Widget details;

  /// Opens the song (Song Stats in C4).
  final VoidCallback? onTap;

  /// Charts 2.0 C4: the song's playback actions.
  final VoidCallback? onLongPress;

  @override
  State<ChartCompactRow> createState() => _ChartCompactRowState();
}

class _ChartCompactRowState extends State<ChartCompactRow> {
  bool _open = false;

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
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                // The rank keeps up to three digits at any text size,
                // without taking the title's room.
                final rankWidth = scaler.scale(34).clamp(34.0, 56.0);
                const movementWidth = 76.0;
                final fixed = rankWidth + 8 + 44 + 10 + 6 + movementWidth;
                // Too little room for a readable title beside the
                // movement: it moves under the title instead.
                final stacked = constraints.maxWidth - fixed < 120;

                final rank = SizedBox(
                  width: rankWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.tier == ChartRowTier.featured)
                        Icon(
                          Icons.emoji_events_rounded,
                          key: const ValueKey<String>('charts-number-one'),
                          size: 16,
                          color: sonusThemeIsGreyscale(colors.accentPrimary)
                              ? colors.textPrimary
                              : colors.accentPrimary,
                        ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${entry.rank}',
                          key: ValueKey<String>('charts-rank-$id'),
                          textAlign: TextAlign.center,
                          style:
                              (widget.tier == ChartRowTier.compact
                                      ? theme.textTheme.titleMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(
                                    color: entry.isOffChartStanding
                                        ? colors.textSecondary
                                        : colors.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                        ),
                      ),
                    ],
                  ),
                );
                final hasAchievement =
                    widget.movement.achievement != ChartAchievement.none;
                final achievement = ChartMovementIndicator(
                  entry: entry,
                  movement: widget.movement,
                  part: ChartIndicatorPart.achievement,
                );
                final move = ChartMovementIndicator(
                  entry: entry,
                  movement: widget.movement,
                  part: ChartIndicatorPart.movement,
                );
                final title = Text(
                  widget.title,
                  maxLines: stacked ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
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
                      size: 44,
                      placeholderIcon: widget.fallbackIcon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 2),
                                // Scale down rather than overflow.
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      move,
                                      if (hasAchievement) ...[
                                        const SizedBox(width: 6),
                                        achievement,
                                      ],
                                    ],
                                  ),
                                ),
                                subtitle,
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                Row(
                                  children: [
                                    if (hasAchievement) ...[
                                      // Scales down rather than overflow
                                      // at large text.
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: achievement,
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
                    if (!stacked) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: movementWidth,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: move,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    // Expanded, the row becomes the entry's full card (no repeated rank
    // or movement), with a way back.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open) ...[
          const SizedBox(height: 6),
          widget.details,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: ValueKey<String>('charts-row-collapse-$id'),
              onPressed: () => setState(() => _open = false),
              icon: const Icon(Icons.expand_less_rounded),
              label: const Text('Hide details'),
            ),
          ),
        ] else
          Row(
            children: [
              Expanded(child: row),
              IconButton(
                key: ValueKey<String>('charts-row-expand-$id'),
                tooltip: 'Show details',
                onPressed: () => setState(() => _open = true),
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        if (widget.tier == ChartRowTier.compact)
          Divider(height: 1, color: colors.divider),
      ],
    );
  }
}
