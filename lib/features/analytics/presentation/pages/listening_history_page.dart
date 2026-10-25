import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../application/models/listening_history_entry.dart';
import '../../application/services/listening_history_service.dart';
import '../../domain/entities/playback_session.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../controllers/listening_history_controller.dart';

class ListeningHistoryPage extends StatefulWidget {
  const ListeningHistoryPage({super.key, this.controller});

  final ListeningHistoryController? controller;

  @override
  State<ListeningHistoryPage> createState() => _ListeningHistoryPageState();
}

class _ListeningHistoryPageState extends State<ListeningHistoryPage> {
  ListeningHistoryController? _controller;

  PlaybackSessionRepository? _playbackSessions;
  QualifiedPlayRepository? _qualifiedPlays;

  bool _ownsController = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final suppliedController = widget.controller;

    if (suppliedController != null) {
      if (!identical(_controller, suppliedController)) {
        _disposeOwnedController();

        _controller = suppliedController;
        _ownsController = false;
      }

      return;
    }

    final playbackSessions = context.watch<PlaybackSessionRepository?>();
    final qualifiedPlays = context.watch<QualifiedPlayRepository?>();

    if (playbackSessions == null || qualifiedPlays == null) {
      _playbackSessions = playbackSessions;
      _qualifiedPlays = qualifiedPlays;

      _disposeOwnedController();
      _controller = null;

      return;
    }

    if (identical(playbackSessions, _playbackSessions) &&
        identical(qualifiedPlays, _qualifiedPlays) &&
        _controller != null) {
      return;
    }

    _playbackSessions = playbackSessions;
    _qualifiedPlays = qualifiedPlays;

    _disposeOwnedController();

    final controller = ListeningHistoryController(
      service: ListeningHistoryService(
        playbackSessions: playbackSessions,
        qualifiedPlays: qualifiedPlays,
      ),
    );

    _controller = controller;
    _ownsController = true;

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('listening-history-page'),
      appBar: AppBar(
        title: const Text('Listening history'),
        actions: [
          if (controller != null)
            ListenableBuilder(
              listenable: controller,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.hasDateFilter)
                      IconButton(
                        key: const ValueKey<String>(
                          'listening-history-clear-filter',
                        ),
                        tooltip: 'Clear date filter',
                        onPressed: controller.isLoading
                            ? null
                            : () {
                                unawaited(controller.clearDateRange());
                              },
                        icon: const Icon(Icons.filter_alt_off_rounded),
                      ),
                    IconButton(
                      key: const ValueKey<String>(
                        'listening-history-filter-button',
                      ),
                      tooltip: 'Filter by date',
                      onPressed: controller.isLoading
                          ? null
                          : () {
                              unawaited(_chooseDateRange(controller));
                            },
                      icon: Icon(
                        controller.hasDateFilter
                            ? Icons.filter_alt_rounded
                            : Icons.filter_alt_outlined,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: controller == null
          ? const _InitializingState()
          : ListenableBuilder(
              listenable: controller,
              builder: (context, child) {
                return _HistoryBody(controller: controller);
              },
            ),
    );
  }

  Future<void> _chooseDateRange(ListeningHistoryController controller) async {
    final now = DateTime.now();

    final initialStart = controller.startedAtOrAfter?.toLocal();
    final initialBefore = controller.startedBefore?.toLocal();

    final initialRange = initialStart != null && initialBefore != null
        ? DateTimeRange(
            start: DateTime(
              initialStart.year,
              initialStart.month,
              initialStart.day,
            ),
            end: DateTime(
              initialBefore.year,
              initialBefore.month,
              initialBefore.day,
            ).subtract(const Duration(days: 1)),
          )
        : null;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
    );

    if (range == null || !mounted) {
      return;
    }

    final startLocal = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );

    final endExclusiveLocal = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));

    await controller.setDateRange(
      startedAtOrAfter: startLocal.toUtc(),
      startedBefore: endExclusiveLocal.toUtc(),
    );
  }

  void _disposeOwnedController() {
    if (_ownsController) {
      _controller?.dispose();
    }

    _ownsController = false;
  }

  @override
  void dispose() {
    _disposeOwnedController();
    super.dispose();
  }
}

class _InitializingState extends StatelessWidget {
  const _InitializingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey<String>('listening-history-initializing'),
      child: CircularProgressIndicator(),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.controller});

  final ListeningHistoryController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && controller.entries.isEmpty) {
      return const Center(
        key: ValueKey<String>('listening-history-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (controller.hasError && controller.entries.isEmpty) {
      return _HistoryErrorState(controller: controller);
    }

    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);

    if (controller.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          key: const ValueKey<String>('listening-history-empty'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Icon(
              Icons.history_rounded,
              size: 48,
              color: tokens.colors.textSecondary,
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'No listening history yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tokens.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Songs you listen to will appear here, including sessions that do not qualify as streams.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final gutter = tokens.metrics.pageGutter;

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        key: const ValueKey<String>('listening-history-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 24),
        itemCount:
            controller.entries.length +
            (controller.hasMore || controller.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < controller.entries.length) {
            return _HistoryEntryCard(entry: controller.entries[index]);
          }

          return _LoadMoreSection(controller: controller);
        },
      ),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({required this.controller});

  final ListeningHistoryController controller;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Center(
      key: const ValueKey<String>('listening-history-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load listening history.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try again in a moment.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey<String>('listening-history-retry'),
              onPressed: controller.isLoading
                  ? null
                  : () {
                      unawaited(controller.refresh());
                    },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final ListeningHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final session = entry.session;
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final localStartedAt = session.startedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);

    final dateText = localizations.formatMediumDate(localStartedAt);
    final timeText = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localStartedAt),
    );

    return Container(
      key: ValueKey<String>('listening-history-entry-${session.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The badge sits beside the title, or beneath it when the
            // text-scaled width is too narrow for both.
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.songTitle,
                      key: ValueKey<String>(
                        'listening-history-title-${session.id}',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.artistName,
                      key: ValueKey<String>(
                        'listening-history-artist-${session.id}',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                );
                final scale = MediaQuery.textScalerOf(context).scale(1);

                if (constraints.maxWidth / scale < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      const SizedBox(height: 8),
                      _QualificationBadge(entry: entry),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    _QualificationBadge(entry: entry),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              _albumLabel(session),
              key: ValueKey<String>('listening-history-album-${session.id}'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$dateText at $timeText',
              key: ValueKey<String>('listening-history-time-${session.id}'),
              style: detailStyle,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'Listened ${_formatDuration(session.listenedDuration)}',
                  key: ValueKey<String>(
                    'listening-history-duration-${session.id}',
                  ),
                  style: detailStyle?.copyWith(color: colors.textPrimary),
                ),
                Text(
                  _endReasonLabel(session.endReason),
                  key: ValueKey<String>(
                    'listening-history-end-reason-${session.id}',
                  ),
                  style: detailStyle,
                ),
              ],
            ),
            if (entry.qualifiedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                _qualifiedAtLabel(context, entry.qualifiedAt!),
                key: ValueKey<String>(
                  'listening-history-qualified-at-${session.id}',
                ),
                style: detailStyle,
              ),
            ],
            if (session.sourceContext?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                'Source: ${session.sourceContext}',
                key: ValueKey<String>('listening-history-source-${session.id}'),
                style: detailStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _albumLabel(PlaybackSession session) {
    final edition = session.albumEditionTitle.trim();

    if (edition.isEmpty || edition == session.albumTitle.trim()) {
      return session.albumTitle;
    }

    return '${session.albumTitle} • $edition';
  }
}

class _QualificationBadge extends StatelessWidget {
  const _QualificationBadge({required this.entry});

  final ListeningHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final qualified = entry.isQualified;
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    // The word carries the meaning; the icon and accent border reinforce it.
    return Chip(
      key: ValueKey<String>('listening-history-qualified-${entry.session.id}'),
      avatar: Icon(
        qualified ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 18,
        color: qualified ? colors.accentPrimary : colors.textSecondary,
      ),
      label: Text(qualified ? 'Qualified' : 'Not qualified'),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: colors.raisedSurface,
      side: BorderSide(color: qualified ? colors.accentPrimary : colors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LoadMoreSection extends StatelessWidget {
  const _LoadMoreSection({required this.controller});

  final ListeningHistoryController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoadingMore) {
      return const Padding(
        key: ValueKey<String>('listening-history-loading-more'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: OutlinedButton.icon(
          key: const ValueKey<String>('listening-history-load-more'),
          onPressed: () {
            unawaited(controller.loadMore());
          },
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('Load more'),
        ),
      ),
    );
  }
}

String _qualifiedAtLabel(BuildContext context, DateTime qualifiedAt) {
  final local = qualifiedAt.toLocal();
  final localizations = MaterialLocalizations.of(context);

  return 'Qualified ${localizations.formatMediumDate(local)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 1 << 31);

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  }

  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }

  return '${seconds}s';
}

String _endReasonLabel(PlaybackSessionEndReason? reason) {
  return switch (reason) {
    PlaybackSessionEndReason.completed => 'Completed',
    PlaybackSessionEndReason.skipped => 'Skipped',
    PlaybackSessionEndReason.stopped => 'Stopped',
    PlaybackSessionEndReason.replaced => 'Replaced',
    PlaybackSessionEndReason.interrupted => 'Interrupted',
    PlaybackSessionEndReason.failed => 'Failed',
    null => 'In progress',
  };
}
