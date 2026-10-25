import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_type.dart';
import 'chart_movement_indicator.dart';

/// Why a chart entry cannot be opened, shown as a text badge.
enum ChartEntryStatus {
  blacklisted('BLACKLISTED', 'Blacklisted'),
  unavailable('UNAVAILABLE', 'Unavailable'),
  historical('HISTORICAL', 'No longer in your library');

  const ChartEntryStatus(this.label, this.spokenLabel);

  final String label;
  final String spokenLabel;
}

/// One position on a Sonus chart, laid out in the Revision 9 order: rank
/// and movement, artwork, title and artist, then statistics.
///
/// Positions 1–100 are the official chart and sit on a card surface;
/// extended standings (101–200) sit flat on the page with an EXTENDED
/// badge, so they never read as official entries.
class ChartEntryCard extends StatefulWidget {
  const ChartEntryCard({
    super.key,
    required this.entry,
    required this.chartType,
    required this.artworkPath,
    this.onTap,
    this.status,
    this.isAllTime = false,
    this.weeklyPeakRank,
  });

  /// Displayed artwork size. Images are decoded at this size so a 200-row
  /// chart doesn't hold full-resolution artwork.
  static const double artworkSize = 64;

  /// The rank column's width at 1x text; it grows with the text scale. It
  /// is fixed rather than sized to content, so artwork lines up on every
  /// row whether the movement reads "NEW", "RE-ENTRY" or an arrow.
  static const double rankColumnWidth = 64;

  /// Below this the details stack under the rank and artwork. At 360dp the
  /// side-by-side layout leaves about 122dp, which still fits two lines.
  static const double minDetailsWidth = 120;

  final ChartEntry entry;
  final ChartType chartType;
  final String? artworkPath;

  /// Null leaves the entry visible but not interactive.
  final VoidCallback? onTap;
  final ChartEntryStatus? status;

  /// Whether the entry is on the permanent all-time chart. There, streams
  /// are lifetime totals, the comparison is the all-time rank at the start
  /// of this week, and there are no chart weeks to count.
  final bool isAllTime;

  /// On the all-time chart, the best position reached on a finalized weekly
  /// chart, shown apart from the all-time peak.
  final int? weeklyPeakRank;

  /// Visible text for the position being compared with: last week's official
  /// rank on a weekly chart, or the all-time rank at the start of this week.
  /// Without one the line shows a neutral dash.
  static String lastWeekText(ChartEntry entry, {bool isAllTime = false}) {
    final previous = entry.previousFinalRank;
    final label = isAllTime ? 'Start of week' : 'Last week';

    return previous == null ? '$label —' : '$label #$previous';
  }

  /// The single label a screen reader announces for the whole card.
  static String semanticLabelFor(
    ChartEntry entry, {
    required String subtitle,
    ChartEntryStatus? status,
    bool isAllTime = false,
    int? weeklyPeakRank,
  }) {
    final previous = entry.previousFinalRank;
    final weeks = entry.weeksOnChart;

    return [
      'Number ${entry.rank}',
      if (entry.isOffChartStanding) 'extended standing',
      ChartMovementIndicator.semanticLabelFor(entry),
      entry.entity.title,
      subtitle,
      isAllTime
          ? '${entry.qualifiedStreamCount} lifetime ${sonusCountNoun(entry.qualifiedStreamCount, 'stream')}'
          : '${entry.qualifiedStreamCount} ${sonusCountNoun(entry.qualifiedStreamCount, 'stream')}',
      isAllTime
          ? 'all-time peak number ${entry.peakRank}'
          : 'peak number ${entry.peakRank}',
      if (isAllTime && weeklyPeakRank != null)
        'weekly chart peak number $weeklyPeakRank',
      if (isAllTime)
        previous == null
            ? 'not ranked at the start of this week'
            : 'number $previous at the start of this week'
      else
        previous == null
            ? 'no official position last week'
            : 'last week number $previous',
      if (!isAllTime) '$weeks ${weeks == 1 ? 'week' : 'weeks'} on chart',
      if (status != null) status.spokenLabel,
    ].join(', ');
  }

  /// "Artist • Album" for songs, the artist alone for albums.
  static String subtitleFor(ChartEntry entry, ChartType chartType) {
    final album = entry.entity.albumTitle?.trim();

    return [
      entry.entity.artistName,
      if (chartType == ChartType.songs && album != null && album.isNotEmpty)
        album,
    ].join(' • ');
  }

  @override
  State<ChartEntryCard> createState() => _ChartEntryCardState();
}

class _ChartEntryCardState extends State<ChartEntryCard> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final entry = widget.entry;
    final isExtended = entry.isOffChartStanding;
    final isTopThree = !isExtended && entry.rank <= 3;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);
    final subtitle = ChartEntryCard.subtitleFor(entry, widget.chartType);

    final Color background = isExtended
        ? Colors.transparent
        : isTopThree
        ? colors.raisedSurface
        : colors.surface;

    final details = _EntryDetails(
      entry: entry,
      subtitle: subtitle,
      status: widget.status,
      isAllTime: widget.isAllTime,
      weeklyPeakRank: widget.weeklyPeakRank,
    );
    final rank = _RankColumn(entry: entry, isTopThree: isTopThree);
    final artwork = _ChartArtwork(
      key: ValueKey<String>('charts-artwork-${entry.entity.entityId}'),
      path: widget.artworkPath,
      fallbackIcon: widget.chartType == ChartType.songs
          ? Icons.music_note_rounded
          : Icons.album_rounded,
    );
    final chevron = widget.onTap == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.chevron_right_rounded,
              color: colors.textSecondary,
            ),
          );

    // The button role sits outside; the summary label sits inside the
    // InkWell so it merges into the node that carries the tap and focus
    // actions instead of hiding them.
    return Semantics(
      button: widget.onTap != null,
      container: true,
      child: DecoratedBox(
        // Keyboard focus outline; ink highlights sit beneath the artwork.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: _focused ? Border.all(color: colors.focus, width: 3) : null,
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: isExtended
                ? BorderSide(color: colors.divider)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: _handleFocusChange,
            child: Semantics(
              label: ChartEntryCard.semanticLabelFor(
                entry,
                subtitle: subtitle,
                status: widget.status,
                isAllTime: widget.isAllTime,
                weeklyPeakRank: widget.weeklyPeakRank,
              ),
              excludeSemantics: true,
              child: Stack(
                children: [
                  if (isTopThree && tokens.decoration.showMarks)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(
                        key: ValueKey<String>(
                          'charts-top-accent-${entry.entity.entityId}',
                        ),
                        color: colors.accentPrimary,
                        child: const SizedBox(width: 4),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (_isCompact(context, constraints.maxWidth)) {
                          // Rank, movement and artwork on top; text gets
                          // the full card width underneath.
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  rank,
                                  const SizedBox(width: 10),
                                  artwork,
                                  const Spacer(),
                                  ?chevron,
                                ],
                              ),
                              const SizedBox(height: 10),
                              details,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            rank,
                            const SizedBox(width: 10),
                            artwork,
                            const SizedBox(width: 12),
                            Expanded(child: details),
                            ?chevron,
                          ],
                        );
                      },
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

  /// Whether the details column would be too narrow beside the rank and
  /// artwork, as on a 320px screen or with large text.
  bool _isCompact(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final besideDetails =
        scaler.scale(ChartEntryCard.rankColumnWidth) +
        10 +
        ChartEntryCard.artworkSize +
        12 +
        (widget.onTap == null ? 0 : 28);

    return width - besideDetails < ChartEntryCard.minDetailsWidth;
  }
}

class _RankColumn extends StatelessWidget {
  const _RankColumn({required this.entry, required this.isTopThree});

  final ChartEntry entry;
  final bool isTopThree;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final width = MediaQuery.textScalerOf(
      context,
    ).scale(ChartEntryCard.rankColumnWidth);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.rank}',
            key: ValueKey<String>('charts-rank-${entry.entity.entityId}'),
            textAlign: TextAlign.center,
            style: tokens.text.chartRank.copyWith(
              color: entry.isOffChartStanding
                  ? tokens.colors.textSecondary
                  : tokens.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // "RE-ENTRY" is the widest badge; it shrinks slightly rather
          // than widening the column and misaligning the artwork.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ChartMovementIndicator(entry: entry),
          ),
        ],
      ),
    );
  }
}

class _ChartArtwork extends StatelessWidget {
  const _ChartArtwork({
    super.key,
    required this.path,
    required this.fallbackIcon,
  });

  final String? path;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final normalizedPath = path?.trim();
    final decodeSize =
        (ChartEntryCard.artworkSize * MediaQuery.devicePixelRatioOf(context))
            .round();
    final fallback = SonusArtworkPlaceholder(icon: fallbackIcon, iconSize: 28);

    return SonusArtworkFrame(
      size: ChartEntryCard.artworkSize,
      child: normalizedPath != null && normalizedPath.isNotEmpty
          ? Image.file(
              File(normalizedPath),
              fit: BoxFit.cover,
              cacheWidth: decodeSize,
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }
}

class _EntryDetails extends StatelessWidget {
  const _EntryDetails({
    required this.entry,
    required this.subtitle,
    required this.status,
    required this.isAllTime,
    required this.weeklyPeakRank,
  });

  final ChartEntry entry;
  final String subtitle;
  final ChartEntryStatus? status;
  final bool isAllTime;
  final int? weeklyPeakRank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final statStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final weeks = entry.weeksOnChart;
    final status = this.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.entity.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${entry.qualifiedStreamCount} ${sonusCountNoun(entry.qualifiedStreamCount, 'stream')}',
              style: statStyle?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              isAllTime
                  ? 'All-time peak #${entry.peakRank}'
                  : 'Peak #${entry.peakRank}',
              style: statStyle,
            ),
            if (isAllTime && weeklyPeakRank != null)
              Text('Weekly peak #$weeklyPeakRank', style: statStyle),
            Text(
              ChartEntryCard.lastWeekText(entry, isAllTime: isAllTime),
              key: ValueKey<String>(
                'charts-last-week-${entry.entity.entityId}',
              ),
              style: statStyle,
            ),
            if (!isAllTime)
              Text('$weeks ${weeks == 1 ? 'week' : 'weeks'}', style: statStyle),
            if (entry.isOffChartStanding)
              _Badge(
                key: ValueKey<String>(
                  'charts-extended-${entry.entity.entityId}',
                ),
                label: 'EXTENDED',
                borderColor: colors.border,
              ),
            if (status != null)
              _Badge(
                label: status.label,
                borderColor: status == ChartEntryStatus.historical
                    ? colors.border
                    : theme.colorScheme.error,
              ),
          ],
        ),
      ],
    );
  }
}

/// A small outlined text badge. The word carries the meaning; the border
/// colour only reinforces it.
class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label, required this.borderColor});

  final String label;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tokens.colors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
