import 'package:flutter/material.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_theme.dart';
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

/// Whether the theme is greyscale (Monochrome): no tints, only artwork.
bool chartThemeIsGreyscale(Color accent) =>
    (accent.r - accent.g).abs() < 0.02 && (accent.g - accent.b).abs() < 0.02;

/// #1: a bold frame in the theme's own gradient around the entry's card,
/// with a "No. 1" ribbon. Plain under high contrast, low effects and
/// Decoration Off; greyscale in Monochrome.
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
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients;
    final a = grey ? colors.textSecondary : colors.accentPrimary;
    final b = grey ? colors.textPrimary : colors.accentSecondary;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius + 6);

    return Container(
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius + 4),
          gradient: gradient
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(a.withValues(alpha: 0.22), colors.surface),
                    colors.surface,
                  ],
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 18, color: a),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'No. 1 · $chartName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// #2–10: the entry's card with an accent from its own artwork (theme
/// colours when the artwork has none). Monochrome uses no tint.
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

class _ChartTopTenFrameState extends State<ChartTopTenFrame> {
  SonusArtworkColors? _art;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ChartTopTenFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkPath != widget.artworkPath) _load();
  }

  void _load() {
    final path = widget.artworkPath;
    if (path == _loadedFor) return;
    _loadedFor = path;
    _art = null;
    final brightness = Theme.of(context).brightness;
    (widget.palette ?? SonusArtworkPalette.shared)
        .colorsFor(path, brightness: brightness)
        .then((colors) {
          if (mounted && _loadedFor == path) setState(() => _art = colors);
        });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients && !grey;
    final accent = grey ? colors.border : _art?.accent ?? colors.accentPrimary;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius + 3);
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
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius + 1.5),
        child: widget.child,
      ),
    );
  }
}

/// #11–100 and Bubbling Under: one line per position — rank, genuine
/// artwork, title and artist, and the C2 movement — with the entry's full
/// card one tap away.
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
  });

  final ChartEntry entry;
  final ChartEntryMovement movement;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final IconData fallbackIcon;
  final ChartEntryStatus? status;

  /// The entry's full card, shown when expanded.
  final Widget details;

  /// Opens the song (Song Stats in C4).
  final VoidCallback? onTap;

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
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(34),
                  child: Text(
                    '${entry.rank}',
                    key: ValueKey<String>('charts-rank-$id'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: entry.isOffChartStanding
                          ? colors.textSecondary
                          : colors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SonusArtworkImage(
                  path: widget.artworkPath,
                  size: 44,
                  placeholderIcon: widget.fallbackIcon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          if (widget.movement.achievement !=
                              ChartAchievement.none) ...[
                            ChartMovementIndicator(
                              entry: entry,
                              movement: widget.movement,
                              part: ChartIndicatorPart.achievement,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              status == null
                                  ? widget.subtitle
                                  : '$status · ${widget.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 76),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: ChartMovementIndicator(
                      entry: entry,
                      movement: widget.movement,
                      part: ChartIndicatorPart.movement,
                    ),
                  ),
                ),
              ],
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
        Divider(height: 1, color: colors.divider),
      ],
    );
  }
}
