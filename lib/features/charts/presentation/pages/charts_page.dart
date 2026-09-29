import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';

import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/entities/chart_snapshot.dart';
import '../../domain/models/chart_movement.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../formatters/chart_moment_feed_copy_formatter.dart';
import '../models/charts_presentation_mode.dart';
import '../controllers/charts_controller.dart';

class ChartsPage extends StatelessWidget {
  const ChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChartsController?>();

    if (controller == null) {
      return const _ChartsMessage(
        key: ValueKey<String>('charts-initializing'),
        icon: Icons.bar_chart_rounded,
        title: 'Sonus Hot 100 is getting ready',
        message: 'Your chart data is still initializing.',
      );
    }

    final snapshot = controller.snapshot;

    if (controller.isLoading && snapshot == null) {
      return const Center(
        key: ValueKey<String>('charts-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (controller.hasError && snapshot == null) {
      return _ChartsError(
        key: const ValueKey<String>('charts-error'),
        onRetry: controller.load,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('charts-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          const _ChartsHeader(),
          const SizedBox(height: 18),
          _ChartsPresentationSelector(controller: controller),
          const SizedBox(height: 20),

          if (controller.isShowingCharts) ...[
            _ChartTypeSelector(controller: controller),
            const SizedBox(height: 18),
            _WeekNavigator(controller: controller),
            const SizedBox(height: 18),
            _ViewSizeSelector(controller: controller),

            if (controller.viewSize == ChartViewSize.top200) ...[
              const SizedBox(height: 10),
              const _ExtendedChartNotice(),
            ],

            const SizedBox(height: 22),

            if (controller.hasError && snapshot != null) ...[
              _RefreshErrorBanner(onRetry: controller.refresh),
              const SizedBox(height: 16),
            ],

            if (snapshot == null || snapshot.entries.isEmpty)
              const _ChartsMessage(
                key: ValueKey<String>('charts-empty'),
                icon: Icons.leaderboard_outlined,
                title: 'No chart entries yet',
                message:
                    'Qualified listening this week will build your Sonus Hot 100.',
              )
            else ...[
              _SnapshotSummary(snapshot: snapshot),
              const SizedBox(height: 14),

              for (final entry in snapshot.entries) ...[
                _ChartRow(entry: entry, controller: controller),
                const Divider(height: 1),
              ],
            ],
          ] else
            _MomentsFeed(controller: controller),
        ],
      ),
    );
  }
}

class _ChartsHeader extends StatelessWidget {
  const _ChartsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey<String>('charts-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SONUS',
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 2.4,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Hot 100',
          key: const ValueKey<String>('charts-title'),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _ChartsPresentationSelector extends StatelessWidget {
  const _ChartsPresentationSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartsPresentationMode>(
      key: const ValueKey<String>('charts-presentation-selector'),
      segments: const [
        ButtonSegment<ChartsPresentationMode>(
          value: ChartsPresentationMode.charts,
          label: Text('Charts'),
          icon: Icon(Icons.leaderboard_rounded),
        ),
        ButtonSegment<ChartsPresentationMode>(
          value: ChartsPresentationMode.moments,
          label: Text('Moments'),
          icon: Icon(Icons.auto_awesome_rounded),
        ),
      ],
      selected: {controller.presentationMode},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) {
          return;
        }

        controller.selectPresentationMode(selection.first);
      },
    );
  }
}

class _MomentsFeed extends StatelessWidget {
  const _MomentsFeed({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.hasMomentFeedError && !controller.hasMomentFeedItems) {
      return _ChartsMessage(
        key: const ValueKey<String>('charts-moments-error'),
        icon: Icons.error_outline_rounded,
        title: 'Moments could not be loaded',
        message:
            'Your chart is still available. Try loading your Moments again.',
        action: FilledButton.icon(
          onPressed: controller.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (!controller.hasMomentFeedItems) {
      return const _ChartsMessage(
        key: ValueKey<String>('charts-moments-empty'),
        icon: Icons.auto_awesome_outlined,
        title: 'No Moments yet',
        message:
            'As your Sonus Hot 100 changes, chart milestones and movement will appear here.',
      );
    }

    return Column(
      key: const ValueKey<String>('charts-moments-feed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.hasMomentFeedError) ...[
          _MomentsRefreshErrorBanner(onRetry: controller.refresh),
          const SizedBox(height: 14),
        ],

        for (
          var index = 0;
          index < controller.momentFeedItems.length;
          index++
        ) ...[
          _MomentCard(
            item: controller.momentFeedItems[index],
            controller: controller,
          ),
          if (index != controller.momentFeedItems.length - 1)
            const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.item, required this.controller});

  static const _formatter = ChartMomentFeedCopyFormatter();

  final ChartMomentFeedItem item;
  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final copy = _formatter.format(item);

    final artworkPath = controller.artworkPathForMoment(item);

    final fallbackIcon = item.chartType == ChartType.songs
        ? Icons.music_note_rounded
        : Icons.album_rounded;

    final subjectLabel = switch (item.subjectType) {
      ChartMomentFeedSubjectType.entity =>
        item.chartType == ChartType.songs ? 'SONG' : 'ALBUM',
      ChartMomentFeedSubjectType.artist =>
        item.chartType == ChartType.songs
            ? 'ARTIST \u2022 SONGS'
            : 'ARTIST \u2022 ALBUMS',
    };

    return Material(
      key: ValueKey<String>('charts-moment-${item.id}'),
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartArtwork(
              key: ValueKey<String>('charts-moment-artwork-${item.id}'),
              path: artworkPath,
              fallbackIcon: fallbackIcon,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MomentScopeBadge(item: item),
                      _MomentTypeBadge(label: subjectLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy.headline,
                    key: ValueKey<String>('charts-moment-headline-${item.id}'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    copy.body,
                    key: ValueKey<String>('charts-moment-body-${item.id}'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatMomentContext(item),
                    key: ValueKey<String>('charts-moment-context-${item.id}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentScopeBadge extends StatelessWidget {
  const _MomentScopeBadge({required this.item});

  final ChartMomentFeedItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: ValueKey<String>('charts-moment-scope-${item.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: item.isLive
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        item.isLive ? 'LIVE' : 'FINAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: item.isLive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MomentTypeBadge extends StatelessWidget {
  const _MomentTypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MomentsRefreshErrorBanner extends StatelessWidget {
  const _MomentsRefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('charts-moments-refresh-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Moments refresh failed. Showing the last available feed.',
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _formatMomentContext(ChartMomentFeedItem item) {
  if (item.isLive) {
    final date = item.occurredAt.toLocal();

    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  return 'Chart week ${_formatMomentWeek(item.weekStartUtc, item.weekEndUtc)}';
}

String _formatMomentWeek(DateTime weekStartUtc, DateTime weekEndUtc) {
  final start = weekStartUtc.toUtc();
  final inclusiveEnd = weekEndUtc.toUtc().subtract(const Duration(days: 1));

  final sameMonth =
      start.year == inclusiveEnd.year && start.month == inclusiveEnd.month;

  if (sameMonth) {
    return '${_monthName(start.month)} '
        '${start.day}\u2013${inclusiveEnd.day}, '
        '${start.year}';
  }

  if (start.year == inclusiveEnd.year) {
    return '${_monthName(start.month)} ${start.day} \u2013 '
        '${_monthName(inclusiveEnd.month)} ${inclusiveEnd.day}, '
        '${start.year}';
  }

  return '${_monthName(start.month)} ${start.day}, ${start.year} \u2013 '
      '${_monthName(inclusiveEnd.month)} '
      '${inclusiveEnd.day}, ${inclusiveEnd.year}';
}

class _ChartTypeSelector extends StatelessWidget {
  const _ChartTypeSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartType>(
      key: const ValueKey<String>('charts-type-selector'),
      segments: const [
        ButtonSegment<ChartType>(
          value: ChartType.songs,
          label: Text('Songs'),
          icon: Icon(Icons.music_note_rounded),
        ),
        ButtonSegment<ChartType>(
          value: ChartType.albums,
          label: Text('Albums'),
          icon: Icon(Icons.album_rounded),
        ),
      ],
      selected: {controller.chartType},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) {
          return;
        }

        controller.selectChartType(selection.first);
      },
    );
  }
}

class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;

    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    return Row(
      key: const ValueKey<String>('charts-week-navigation'),
      children: [
        IconButton(
          key: const ValueKey<String>('charts-older-week'),
          tooltip: 'Older chart week',
          onPressed: controller.canGoToOlderWeek
              ? controller.showOlderWeek
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _formatChartWeek(snapshot),
                key: const ValueKey<String>('charts-week-label'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _SnapshotStatusBadge(snapshot: snapshot),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey<String>('charts-calendar'),
          tooltip: 'Choose chart week',
          onPressed: controller.history.isEmpty
              ? null
              : () => _showWeekCalendar(context, controller),
          icon: const Icon(Icons.calendar_month_rounded),
        ),
        IconButton(
          key: const ValueKey<String>('charts-newer-week'),
          tooltip: 'Newer chart week',
          onPressed: controller.canGoToNewerWeek
              ? controller.showNewerWeek
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _SnapshotStatusBadge extends StatelessWidget {
  const _SnapshotStatusBadge({required this.snapshot});

  final ChartSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey<String>('charts-snapshot-status'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: snapshot.isLive
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        snapshot.isLive ? 'LIVE' : 'FINAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: snapshot.isLive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ViewSizeSelector extends StatelessWidget {
  const _ViewSizeSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('charts-size-selector'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final size in ChartViewSize.values) ...[
            ChoiceChip(
              key: ValueKey<String>('charts-size-${size.limit}'),
              label: Text('Top ${size.limit}'),
              selected: controller.viewSize == size,
              onSelected: (_) {
                controller.selectViewSize(size);
              },
            ),
            if (size != ChartViewSize.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ExtendedChartNotice extends StatelessWidget {
  const _ExtendedChartNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey<String>('charts-extended-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Top 100 is the official chart. Positions 101\u2013200 are extended standings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({required this.snapshot});

  final ChartSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      key: const ValueKey<String>('charts-snapshot-summary'),
      children: [
        Expanded(
          child: Text(
            snapshot.chartType == ChartType.songs ? 'Songs' : 'Albums',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          '${snapshot.entries.length} positions',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.entry, required this.controller});

  final ChartEntry entry;
  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.trackForEntry(entry);
    final album = controller.albumForEntry(entry);

    final canInteract = switch (controller.chartType) {
      ChartType.songs => controller.isTrackInteractive(entry),
      ChartType.albums => controller.isAlbumInteractive(entry),
    };

    final artworkPath = switch (controller.chartType) {
      ChartType.songs => track?.artworkPath,
      ChartType.albums => album?.artworkPath,
    };

    final fallbackIcon = controller.chartType == ChartType.songs
        ? Icons.music_note_rounded
        : Icons.album_rounded;

    return Material(
      key: ValueKey<String>('charts-entry-${entry.entity.entityId}'),
      color: entry.rank <= 3
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canInteract
            ? () {
                if (controller.chartType == ChartType.songs && track != null) {
                  unawaited(_showChartTrackContext(context, track));
                  return;
                }

                if (controller.chartType == ChartType.albums && album != null) {
                  _openAlbum(context, album);
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  '${entry.rank}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ChartArtwork(
                path: artworkPath,
                fallbackIcon: fallbackIcon,
                key: ValueKey<String>(
                  'charts-artwork-${entry.entity.entityId}',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ChartMetadata(
                  entry: entry,
                  controller: controller,
                  track: track,
                  album: album,
                ),
              ),
              if (canInteract)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right_rounded),
                ),
            ],
          ),
        ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 64,
        child: normalizedPath != null && normalizedPath.isNotEmpty
            ? Image.file(
                File(normalizedPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _ChartArtworkFallback(icon: fallbackIcon),
              )
            : _ChartArtworkFallback(icon: fallbackIcon),
      ),
    );
  }
}

class _ChartArtworkFallback extends StatelessWidget {
  const _ChartArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 30, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ChartMetadata extends StatelessWidget {
  const _ChartMetadata({
    required this.entry,
    required this.controller,
    required this.track,
    required this.album,
  });

  final ChartEntry entry;
  final ChartsController controller;
  final LibraryTrack? track;
  final LibraryAlbum? album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtitleParts = <String>[
      entry.entity.artistName,
      if (controller.chartType == ChartType.songs &&
          entry.entity.albumTitle != null &&
          entry.entity.albumTitle!.trim().isNotEmpty)
        entry.entity.albumTitle!.trim(),
    ];

    final unavailableLiveTrack =
        controller.isViewingLive &&
        controller.chartType == ChartType.songs &&
        track != null &&
        !controller.isTrackInteractive(entry);

    final missingCurrentEntity = switch (controller.chartType) {
      ChartType.songs => track == null,
      ChartType.albums => album == null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.entity.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitleParts.join(' \u2022 '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MovementLabel(entry: entry),
            Text(
              '${entry.qualifiedStreamCount} streams',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            Text(
              'Peak #${entry.peakRank}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${entry.weeksOnChart} '
              '${entry.weeksOnChart == 1 ? 'week' : 'weeks'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (entry.isOffChartStanding)
              Text(
                'EXTENDED',
                key: ValueKey<String>(
                  'charts-extended-${entry.entity.entityId}',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: colorScheme.primary,
                ),
              ),
            if (unavailableLiveTrack)
              Text(
                track!.isBlocked ? 'BLACKLISTED' : 'UNAVAILABLE',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.error,
                ),
              ),
            if (controller.isViewingHistory && missingCurrentEntity)
              Text(
                'HISTORICAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MovementLabel extends StatelessWidget {
  const _MovementLabel({required this.entry});

  final ChartEntry entry;

  @override
  Widget build(BuildContext context) {
    return Text(
      switch (entry.movement) {
        ChartMovement.newEntry => 'NEW',
        ChartMovement.reentry => 'RE-ENTRY',
        ChartMovement.up => '\u25B2 ${_movementDistance(entry)}',
        ChartMovement.down => '\u25BC ${_movementDistance(entry)}',
        ChartMovement.same => '\u2014',
      },
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  int _movementDistance(ChartEntry entry) {
    final previous = entry.previousFinalRank;

    if (previous == null) {
      return 0;
    }

    return (previous - entry.rank).abs();
  }
}

class _ChartsError extends StatelessWidget {
  const _ChartsError({super.key, required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _ChartsMessage(
      icon: Icons.error_outline_rounded,
      title: 'Sonus Hot 100 could not be loaded',
      message: 'Try loading your chart again.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    );
  }
}

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey<String>('charts-refresh-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 10),
            const Expanded(child: Text('Chart refresh failed.')),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ChartsMessage extends StatelessWidget {
  const _ChartsMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

Future<void> _showWeekCalendar(
  BuildContext context,
  ChartsController controller,
) async {
  final history = controller.history;

  if (history.isEmpty) {
    return;
  }

  final availableDates = {
    for (final snapshot in history)
      DateUtils.dateOnly(snapshot.weekStartUtc.toLocal()),
  };

  final earliest = history.last.weekStartUtc.toLocal();
  final latest = history.first.weekStartUtc.toLocal();

  final selected = await showDatePicker(
    context: context,
    helpText: 'Choose a Sonus Hot 100 week',
    initialDate:
        controller.selectedHistoricalSnapshot?.weekStartUtc.toLocal() ?? latest,
    firstDate: DateUtils.dateOnly(earliest),
    lastDate: DateUtils.dateOnly(latest),
    selectableDayPredicate: (date) {
      return availableDates.contains(DateUtils.dateOnly(date));
    },
  );

  if (selected == null) {
    return;
  }

  for (final snapshot in history) {
    final localStart = DateUtils.dateOnly(snapshot.weekStartUtc.toLocal());

    if (localStart == DateUtils.dateOnly(selected)) {
      controller.selectHistoricalWeek(snapshot.weekStartUtc);
      return;
    }
  }
}

Future<void> _showChartTrackContext(
  BuildContext context,
  LibraryTrack track,
) async {
  if (track.isBlocked ||
      !track.isAvailable ||
      track.filePath == null ||
      track.filePath!.trim().isEmpty) {
    return;
  }

  final playback = context.read<PlaybackCoordinator?>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artistName} \u2022 ${track.albumTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Play'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playTrack(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Play next'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playNext(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Add to queue'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.addToQueue(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Go to album'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumProfilePage(
                        albumId: track.albumId,
                        initialAlbumTitle: track.albumTitle,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Go to artist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArtistProfilePage(
                        artistId: track.artistId,
                        initialArtistName: track.artistName,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _openAlbum(BuildContext context, LibraryAlbum album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumProfilePage(
        albumId: album.albumId,
        initialAlbumTitle: album.title,
      ),
    ),
  );
}

String _formatChartWeek(ChartSnapshot snapshot) {
  final start = snapshot.weekStartUtc.toUtc();

  final inclusiveEnd = snapshot.weekEndUtc.toUtc().subtract(
    const Duration(days: 1),
  );

  final sameMonth =
      start.year == inclusiveEnd.year && start.month == inclusiveEnd.month;

  if (sameMonth) {
    return '${_monthName(start.month)} '
        '${start.day}\u2013${inclusiveEnd.day}, '
        '${start.year}';
  }

  if (start.year == inclusiveEnd.year) {
    return '${_monthName(start.month)} ${start.day} \u2013 '
        '${_monthName(inclusiveEnd.month)} ${inclusiveEnd.day}, '
        '${start.year}';
  }

  return '${_monthName(start.month)} ${start.day}, ${start.year} \u2013 '
      '${_monthName(inclusiveEnd.month)} '
      '${inclusiveEnd.day}, ${inclusiveEnd.year}';
}

String _monthName(int month) {
  return const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}
