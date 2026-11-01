import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';

import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/entities/chart_entry.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/models/chart_view_size.dart';
import '../news/moment_post_card.dart';
import '../editorial/moment_category.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_publisher.dart';
import '../models/chart_week_label.dart';
import '../models/charts_presentation_mode.dart';
import '../controllers/charts_controller.dart';
import '../widgets/all_time_chart_cards.dart';
import '../widgets/chart_board_rows.dart';
import '../widgets/chart_entry_card.dart';
import '../widgets/chart_extended_divider.dart';
import '../widgets/chart_info_sheet.dart';

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

    final hasChart = controller.hasChart;

    if (controller.isLoading && !hasChart) {
      return const Center(
        key: ValueKey<String>('charts-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (controller.hasError && !hasChart) {
      return _ChartsError(
        key: const ValueKey<String>('charts-error'),
        onRetry: controller.load,
      );
    }

    final entries = controller.isShowingCharts
        ? controller.boardEntries
        : const <ChartEntry>[];

    // Each chart board keeps its own scroll position (Charts 2.0 C3).
    final scrollKey = controller.isShowingCharts
        ? 'charts-scroll-${controller.chartType.name}-${controller.board.name}'
        : 'charts-scroll';

    return _ScrollToTopHost(
      builder: (scroll, rows) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: _ChartScrollRail(
          controller: scroll,
          enabled: entries.length > 25,
          child: CustomScrollView(
            key: PageStorageKey<String>(scrollKey),
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                sliver: SliverList.list(
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
                      _ChartBoardSelector(controller: controller),
                      if (controller.board == ChartBoard.top100) ...[
                        const SizedBox(height: 14),
                        _ViewSizeSelector(controller: controller),
                      ],

                      const SizedBox(height: 22),

                      if (controller.hasError && hasChart) ...[
                        _RefreshErrorBanner(onRetry: controller.refresh),
                        const SizedBox(height: 16),
                      ],

                      if (entries.isEmpty &&
                          controller.board == ChartBoard.extended)
                        _ChartsMessage(
                          key: const ValueKey<String>('charts-board-empty'),
                          icon: Icons.bubble_chart_outlined,
                          title: controller.chartType == ChartType.songs
                              ? 'Nothing is bubbling under yet'
                              : 'No positions below #100 yet',
                          message: controller.chartType == ChartType.songs
                              ? 'Songs ranked #101–200 appear here once more than 100 songs have qualified listens.'
                              : 'Releases ranked #101–200 appear here once more than 100 releases have qualified listens.',
                        )
                      else if (entries.isEmpty)
                        controller.isViewingThisWeek
                            ? const _ChartsMessage(
                                key: ValueKey<String>('charts-empty'),
                                icon: Icons.leaderboard_outlined,
                                title: 'No chart entries this week yet',
                                message:
                                    'Qualified listens this week will appear here as you listen.',
                              )
                            : const _ChartsMessage(
                                key: ValueKey<String>('charts-empty'),
                                icon: Icons.leaderboard_outlined,
                                title: 'No chart entries yet',
                                message:
                                    'Every qualified listen counts toward your Sonus Hot 100 career standings.',
                              )
                      else ...[
                        _ChartSummary(
                          chartType: controller.chartType,
                          board: controller.board,
                          positionCount: entries.length,
                          onJump: () => _jumpToRank(
                            context,
                            scroll: scroll,
                            rows: rows,
                            entries: entries,
                          ),
                          isWeeklyHistory: controller.isViewingHistory,
                          isThisWeek: controller.isViewingThisWeek,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ] else
                      _MomentsFeedHeader(controller: controller),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: controller.isShowingMoments
                    ? _momentsFeedSliver(controller)
                    : SliverList.builder(
                        // Built lazily: only the rows on screen exist.
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final compact = _isCompactRow(controller, entry);
                          return _RankAnchor(
                            rank: entry.rank,
                            rows: rows,
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: compact ? 0 : 10,
                              ),
                              child: _ChartEntryItem(
                                entry: entry,
                                controller: controller,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hosts a scroll view with a floating "Back to top" button that appears
/// once the page is scrolled well down (Charts 2.0 C1). The button sits in
/// the page, which ends above the mini-player, so it never covers it.
class _ScrollToTopHost extends StatefulWidget {
  const _ScrollToTopHost({required this.builder});

  final Widget Function(ScrollController controller, _ChartRows rows) builder;

  @override
  State<_ScrollToTopHost> createState() => _ScrollToTopHostState();
}

class _ScrollToTopHostState extends State<_ScrollToTopHost> {
  static const double _showAfter = 800;

  final ScrollController _scroll = ScrollController();
  final _ChartRows _rows = _ChartRows();
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
  }

  void _update() {
    final show = _scroll.hasClients && _scroll.offset > _showAfter;
    if (show != _show) setState(() => _show = show);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    final motion = SonusTheme.of(context).motion;
    if (motion.reduced) {
      _scroll.jumpTo(0);
    } else {
      unawaited(
        _scroll.animateTo(0, duration: motion.long, curve: motion.curve),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = SonusTheme.of(context).motion;
    return Stack(
      children: [
        widget.builder(_scroll, _rows),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: IgnorePointer(
            ignoring: !_show,
            child: AnimatedOpacity(
              opacity: _show ? 1 : 0,
              duration: motion.short,
              child: FloatingActionButton.small(
                key: const ValueKey<String>('charts-scroll-to-top'),
                heroTag: null,
                tooltip: 'Back to top',
                onPressed: _show ? _toTop : null,
                child: const Icon(Icons.vertical_align_top_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartsHeader extends StatelessWidget {
  const _ChartsHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);

    // The page's featured header carries the theme's texture and motif.
    return Stack(
      children: [
        const Positioned.fill(child: SonusSurfaceTexture()),
        Column(
          key: const ValueKey<String>('charts-header'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SONUS',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
                color: tokens.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Semantics(
              header: true,
              child: Text(
                'Hot 100',
                key: const ValueKey<String>('charts-title'),
                style: tokens.text.pageTitle.copyWith(
                  color: tokens.colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            if (tokens.decoration.showMarks) ...[
              SizedBox(height: tokens.metrics.spaceSm),
              const SonusMotifMark(),
            ],
          ],
        ),
      ],
    );
  }
}

/// Selector styling for the Charts page only. It is applied locally so the
/// global theme, and every other screen's selectors, stay unchanged.
ButtonStyle _chartsSegmentedStyle(SonusThemeData tokens) {
  final colors = tokens.colors;

  return SegmentedButton.styleFrom(
    foregroundColor: colors.textSecondary,
    selectedForegroundColor: colors.textPrimary,
    selectedBackgroundColor: colors.selection,
    side: BorderSide(color: colors.border),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
    ),
  );
}

/// A decorative segment icon, dropped with large text so labels such as
/// "Moments" keep their width instead of breaking mid-word. The selection
/// checkmark stays, so the selected segment never relies on colour alone.
Widget? _segmentIcon(BuildContext context, IconData icon) {
  final isLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;

  return isLargeText ? null : Icon(icon);
}

class _ChartsPresentationSelector extends StatelessWidget {
  const _ChartsPresentationSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final hasNewMoments = controller.hasNewMoments;

    return SegmentedButton<ChartsPresentationMode>(
      key: const ValueKey<String>('charts-presentation-selector'),
      style: _chartsSegmentedStyle(SonusTheme.of(context)),
      segments: [
        ButtonSegment<ChartsPresentationMode>(
          value: ChartsPresentationMode.charts,
          label: Text('Charts'),
          icon: _segmentIcon(context, Icons.leaderboard_rounded),
        ),
        ButtonSegment<ChartsPresentationMode>(
          value: ChartsPresentationMode.moments,
          label: hasNewMoments
              ? Semantics(
                  label: 'Moments, new stories',
                  excludeSemantics: true,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text('Moments')),
                      SizedBox(width: 6),
                      _NewMomentsDot(),
                    ],
                  ),
                )
              : const Text('Moments'),
          icon: _segmentIcon(context, Icons.auto_awesome_rounded),
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

/// Moments has stories newer than when it was last open (SN-50 F-Q26). The
/// segment also says "new stories" to screen readers.
class _NewMomentsDot extends StatelessWidget {
  const _NewMomentsDot();

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Container(
      key: const ValueKey<String>('charts-moments-new-dot'),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: colors.accentPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.textPrimary, width: 1.5),
      ),
    );
  }
}

/// Above the stories: the feed's error and empty states, its filters and
/// the refresh banner.
class _MomentsFeedHeader extends StatelessWidget {
  const _MomentsFeedHeader({required this.controller});

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

    final hasMore = controller.hasMoreMoments;

    if (controller.momentStories.isEmpty && !hasMore) {
      return const _ChartsMessage(
        key: ValueKey<String>('charts-moments-empty'),
        icon: Icons.auto_awesome_outlined,
        title: 'No Moments yet',
        message:
            'Debuts, new peaks and number ones on your Sonus Hot 100 will appear here as they happen.',
      );
    }

    final archive = controller.momentsSection == MomentsSection.archive;
    final narrowed =
        controller.isFilteringMoments ||
        (archive &&
            (controller.momentQuery.trim().isNotEmpty ||
                controller.momentWeek != null));
    final complete = !controller.hasMoreForSection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.hasMomentFeedError) ...[
          _MomentsRefreshErrorBanner(onRetry: controller.refresh),
          const SizedBox(height: 14),
        ],
        SonusSegmentedSelector<MomentsSection>(
          key: const ValueKey<String>('charts-moments-section'),
          segments: const [
            SonusSegment(
              value: MomentsSection.recent,
              icon: Icons.bolt_rounded,
              label: 'Recent',
            ),
            SonusSegment(
              value: MomentsSection.archive,
              icon: Icons.inventory_2_outlined,
              label: 'Archive',
            ),
          ],
          selected: controller.momentsSection,
          onChanged: controller.selectMomentsSection,
        ),
        const SizedBox(height: 12),
        if (archive) ...[
          _MomentsArchiveSearch(controller: controller),
          const SizedBox(height: 10),
        ],
        _MomentsFilters(controller: controller),
        const SizedBox(height: 16),
        if (controller.sectionMomentStories.isEmpty && complete && !narrowed)
          _ChartsMessage(
            key: ValueKey<String>(
              'charts-moments-${archive ? 'archive' : 'recent'}-empty',
            ),
            icon: archive
                ? Icons.inventory_2_outlined
                : Icons.auto_awesome_outlined,
            title: archive
                ? 'No archived Moments yet'
                : 'No Moments this chart week yet',
            message: archive
                ? 'Stories move here when their chart week is finalized.'
                : 'Earlier stories are in the Archive.',
          ),
        if (controller.sectionMomentStories.isEmpty && complete && narrowed)
          _ChartsMessage(
            key: const ValueKey<String>('charts-moments-filtered-empty'),
            icon: Icons.filter_list_off_rounded,
            title: 'No Moments match these filters',
            message: 'Try another category or publisher.',
            action: OutlinedButton(
              onPressed: () {
                controller.selectMomentCategory(null);
                controller.selectMomentPublisher(null);
                controller.searchMoments('');
                controller.selectMomentWeek(null);
              },
              child: const Text('Show all Moments'),
            ),
          ),
      ],
    );
  }
}

/// One chronological feed, narrowed by category and publisher (F-Q25),
/// with one compact menu each (Charts 2.0 C1). Both apply together.
class _MomentsFilters extends StatelessWidget {
  const _MomentsFilters({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey<String>('charts-moments-filters'),
      spacing: 8,
      runSpacing: 8,
      children: [
        _MomentsMenu<MomentCategory>(
          label: 'Category',
          allLabel: 'All stories',
          values: MomentCategory.values,
          labelOf: (category) => category.label,
          selected: controller.momentCategory,
          onSelected: controller.selectMomentCategory,
        ),
        _MomentsMenu<MomentPublisher>(
          label: 'Publisher',
          allLabel: 'All publishers',
          values: MomentPublisher.values,
          labelOf: (publisher) => publisher.label,
          selected: controller.momentPublisher,
          onSelected: controller.selectMomentPublisher,
        ),
        if (controller.momentsSection == MomentsSection.archive)
          _MomentsWeekMenu(controller: controller),
      ],
    );
  }
}

class _MomentsMenu<T extends Enum> extends StatelessWidget {
  const _MomentsMenu({
    required this.label,
    required this.allLabel,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String allLabel;
  final List<T> values;
  final String Function(T value) labelOf;
  final T? selected;
  final void Function(T? value) onSelected;

  @override
  Widget build(BuildContext context) {
    final current = selected;
    return _MenuButton<T?>(
      key: ValueKey<String>('charts-moments-filter-$label'),
      label: label,
      value: current == null ? allLabel : labelOf(current),
      active: current != null,
      items: [
        (null, allLabel),
        for (final value in values) (value, labelOf(value)),
      ],
      itemKey: (value) =>
          ValueKey<String>('charts-moments-filter-$label-${value?.name}'),
      selected: current,
      onSelected: onSelected,
    );
  }
}

class _MomentsWeekMenu extends StatelessWidget {
  const _MomentsWeekMenu({required this.controller});

  final ChartsController controller;

  static String _week(DateTime startUtc) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = startUtc.toLocal();
    return 'Week of ${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final week = controller.momentWeek;
    return _MenuButton<DateTime?>(
      key: const ValueKey<String>('charts-moments-week'),
      label: 'Week',
      value: week == null ? 'All weeks' : _week(week),
      active: week != null,
      items: [
        (null, 'All weeks'),
        for (final start in controller.archivedMomentWeeks)
          (start, _week(start)),
      ],
      itemKey: (value) => ValueKey<String>(
        'charts-moments-week-${value?.millisecondsSinceEpoch}',
      ),
      selected: week,
      onSelected: controller.selectMomentWeek,
    );
  }
}

/// A compact "Label: value" menu button, at least 44 dp tall.
class _MenuButton<V> extends StatelessWidget {
  const _MenuButton({
    super.key,
    required this.label,
    required this.value,
    required this.active,
    required this.items,
    required this.itemKey,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool active;
  final List<(V, String)> items;
  final Key Function(V value) itemKey;
  final V selected;
  final void Function(V value) onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: PopupMenuButton<int>(
        tooltip: label,
        onSelected: (index) => onSelected(items[index].$1),
        itemBuilder: (_) => [
          for (var i = 0; i < items.length; i++)
            CheckedPopupMenuItem<int>(
              key: itemKey(items[i].$1),
              value: i,
              checked: items[i].$1 == selected,
              child: Text(items[i].$2),
            ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? colors.accentPrimary.withValues(alpha: 0.16)
                : colors.raisedSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active ? colors.accentPrimary : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label: ',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      TextSpan(
                        text: value,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Archive search by headline, song, artist or release.
class _MomentsArchiveSearch extends StatefulWidget {
  const _MomentsArchiveSearch({required this.controller});

  final ChartsController controller;

  @override
  State<_MomentsArchiveSearch> createState() => _MomentsArchiveSearchState();
}

class _MomentsArchiveSearchState extends State<_MomentsArchiveSearch> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.momentQuery,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('charts-moments-search'),
      controller: _text,
      onChanged: widget.controller.searchMoments,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search artist, song, release or headline',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _text.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _text.clear();
                  widget.controller.searchMoments('');
                  setState(() {});
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
        isDense: true,
      ),
    );
  }
}

/// The stories, built as they scroll into view, then the next page.
Widget _momentsFeedSliver(ChartsController controller) {
  final stories = controller.sectionMomentStories;
  final hasFooter = controller.hasMoreForSection;
  final now = controller.currentTime();

  return SliverList.builder(
    key: const ValueKey<String>('charts-moments-feed'),
    itemCount: stories.length + (hasFooter ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == stories.length) {
        return _MomentsPageFooter(controller: controller);
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _MomentPost(
          story: stories[index],
          now: now,
          controller: controller,
        ),
      );
    },
  );
}

/// Built only near the end of the loaded stories: reads the next page, or
/// offers a retry when that failed.
class _MomentsPageFooter extends StatelessWidget {
  const _MomentsPageFooter({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.momentPageError != null) {
      return Padding(
        key: const ValueKey<String>('charts-moments-page-error'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            const Text(
              'Older Moments could not be loaded.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.loadMoreMoments()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (!controller.isLoadingMoreMoments) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(controller.loadMoreMoments()),
      );
    }

    return const Padding(
      key: ValueKey<String>('charts-moments-loading-more'),
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Loading older Moments',
        ),
      ),
    );
  }
}

class _MomentPost extends StatelessWidget {
  const _MomentPost({
    required this.story,
    required this.now,
    required this.controller,
  });

  final MomentStory story;
  final DateTime now;
  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final item = story.item;
    final track = controller.trackForMoment(item);
    final album = controller.albumForMoment(item);
    final artist = controller.artistForMoment(item);
    final playable =
        track != null &&
        !track.isBlocked &&
        track.isAvailable &&
        (track.filePath?.trim().isNotEmpty ?? false);

    return MomentPostCard(
      key: ValueKey<String>('charts-moment-${item.id}'),
      story: story,
      now: now,
      credit: controller.creditForMoment(story),
      onOpenSong: playable
          ? () => unawaited(_showChartTrackContext(context, track, [track]))
          : null,
      onOpenAlbum: album == null
          ? null
          : () => unawaited(_openMomentRelease(context, controller, item)),
      onOpenArtist: artist == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistProfilePage(
                  artistId: artist.artistId,
                  initialArtistName: artist.name,
                ),
              ),
            ),
    );
  }
}

/// Opens the edition a Moment happened on, or the primary edition with a
/// note when that edition was removed (SN-50 A-Q29).
Future<void> _openMomentRelease(
  BuildContext context,
  ChartsController controller,
  ChartMomentFeedItem item,
) async {
  final target = await controller.releaseTargetForMoment(item);

  if (target == null || !context.mounted) return;

  if (target.editionRemoved) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'The edition from this story was removed; showing the main edition.',
        ),
      ),
    );
  }

  _openAlbum(context, target.album, editionId: target.editionId);
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

class _ChartTypeSelector extends StatelessWidget {
  const _ChartTypeSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartType>(
      key: const ValueKey<String>('charts-type-selector'),
      style: _chartsSegmentedStyle(SonusTheme.of(context)),
      segments: [
        ButtonSegment<ChartType>(
          value: ChartType.songs,
          label: Text('Songs'),
          icon: _segmentIcon(context, Icons.music_note_rounded),
        ),
        ButtonSegment<ChartType>(
          value: ChartType.albums,
          label: Text('Albums & EPs'),
          icon: _segmentIcon(context, Icons.album_rounded),
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
    final thisWeek = controller.thisWeekSnapshot;

    if (!controller.hasChart) {
      return const SizedBox.shrink();
    }

    final status = snapshot != null
        ? _ChartStatus.finalized
        : thisWeek != null
        ? _ChartStatus.inProgress
        : _ChartStatus.current;

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
                switch (status) {
                  _ChartStatus.current => 'Career standings',
                  _ChartStatus.inProgress => 'This week',
                  _ChartStatus.finalized => chartWeekLabel(
                    snapshot!.weekStartUtc,
                    snapshot.weekEndUtc,
                  ),
                },
                key: const ValueKey<String>('charts-week-label'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _ChartStatusBadge(status: status),
              if (thisWeek != null) ...[
                const SizedBox(height: 6),
                Text(
                  _provisionalNote(thisWeek.weekEndUtc),
                  key: const ValueKey<String>('charts-this-week-note'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SonusTheme.of(context).colors.textSecondary,
                  ),
                ),
              ],
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

/// "Updates as you listen. Final after Oct 31, 2026.": the week's last
/// local day, as the week label reads it.
String _provisionalNote(DateTime weekEndUtc) {
  final end = weekEndUtc.toLocal();
  final lastDay = DateTime(end.year, end.month, end.day - 1);

  return 'Updates as you listen. Final after ${chartShortDate(lastDay)}.';
}

enum _ChartStatus { current, inProgress, finalized }

/// CURRENT for the career standings, IN PROGRESS for This Week, FINAL for
/// a finalized weekly chart.
class _ChartStatusBadge extends StatelessWidget {
  const _ChartStatusBadge({required this.status});

  final _ChartStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final isCurrent = status == _ChartStatus.current;
    final isInProgress = status == _ChartStatus.inProgress;
    final foreground = isCurrent
        ? colors.onAccentPrimary
        : isInProgress
        ? colors.textPrimary
        : colors.textSecondary;

    // CURRENT is filled with the accent, IN PROGRESS is outlined in the
    // accent with a clock, and FINAL is outlined plainly, so the three read
    // differently by shape and text as well as colour.
    return Container(
      key: const ValueKey<String>('charts-snapshot-status'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? colors.accentPrimary : Colors.transparent,
        border: isCurrent
            ? null
            : Border.all(
                color: isInProgress ? colors.accentPrimary : colors.border,
                width: isInProgress ? 1.5 : 1,
              ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInProgress) ...[
            Icon(Icons.schedule_rounded, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              switch (status) {
                _ChartStatus.current => 'CURRENT',
                _ChartStatus.inProgress => 'IN PROGRESS',
                _ChartStatus.finalized => 'FINAL',
              },
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewSizeSelector extends StatelessWidget {
  const _ViewSizeSelector({required this.controller});

  final ChartsController controller;

  /// Positions 101–200 have their own board.
  static final _top100Sizes = [
    for (final size in ChartViewSize.values)
      if (size.limit <= 100) size,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final current = controller.viewSize.limit > 100
        ? ChartViewSize.top100
        : controller.viewSize;

    // Its own scroll storage: without it, this horizontal scroller shares the
    // chart list's slot and reopens at the list's vertical offset.
    return KeyedSubtree(
      key: const PageStorageKey<String>('charts-size-selector-scroll'),
      child: SingleChildScrollView(
        key: const ValueKey<String>('charts-size-selector'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final size in _top100Sizes) ...[
              // Styled here only; the checkmark marks the selection without
              // relying on colour.
              ChoiceChip(
                key: ValueKey<String>('charts-size-${size.limit}'),
                label: Text('Top ${size.limit}'),
                selected: current == size,
                showCheckmark: true,
                selectedColor: colors.selection,
                backgroundColor: Colors.transparent,
                checkmarkColor: colors.textPrimary,
                labelStyle: TextStyle(
                  color: current == size
                      ? colors.textPrimary
                      : colors.textSecondary,
                  fontWeight: current == size
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
                side: BorderSide(color: colors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    tokens.metrics.controlRadius,
                  ),
                ),
                onSelected: (_) {
                  controller.selectViewSize(size);
                },
              ),
              if (size != _top100Sizes.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartSummary extends StatelessWidget {
  const _ChartSummary({
    required this.chartType,
    required this.board,
    required this.onJump,
    required this.positionCount,
    required this.isWeeklyHistory,
    required this.isThisWeek,
  });

  final ChartType chartType;
  final ChartBoard board;
  final VoidCallback onJump;
  final int positionCount;
  final bool isWeeklyHistory;
  final bool isThisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    final name = _boardName(chartType, board);

    // The name and count wrap under each other with large text instead of
    // overflowing; the information button stays at the end of the row.
    return Row(
      key: const ValueKey<String>('charts-snapshot-summary'),
      children: [
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                sonusCount(positionCount, 'position'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (positionCount > 10)
          IconButton(
            key: const ValueKey<String>('charts-jump-to-rank'),
            tooltip: 'Jump to a position',
            icon: Icon(Icons.pin_outlined, color: colors.textSecondary),
            onPressed: onJump,
          ),
        IconButton(
          key: const ValueKey<String>('charts-info-button'),
          tooltip: 'About the $name',
          icon: Icon(Icons.info_outline_rounded, color: colors.textSecondary),
          onPressed: () => showChartInfoSheet(
            context,
            chartType,
            isWeeklyHistory: isWeeklyHistory,
            isThisWeek: isThisWeek,
          ),
        ),
      ],
    );
  }
}

/// Maps one chart entry and the controller's view of it onto a card:
/// artwork, title, interactivity, status badges and longevity.
class _ChartEntryItem extends StatelessWidget {
  const _ChartEntryItem({required this.entry, required this.controller});

  final ChartEntry entry;
  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.trackForEntry(entry);
    final album = controller.albumForEntry(entry);
    final chartType = controller.chartType;

    final canInteract = switch (chartType) {
      ChartType.songs => controller.isTrackInteractive(entry),
      ChartType.albums => controller.isAlbumInteractive(entry),
    };

    final presentation = controller.albumPresentationFor(entry);
    final song = controller.songPresentationFor(entry);
    final artworkPath = switch (chartType) {
      ChartType.songs => track?.artworkPath,
      ChartType.albums =>
        presentation == null ? album?.artworkPath : presentation.artworkPath,
    };
    final longevity = controller.longevityFor(entry);

    final unavailableLiveTrack =
        !controller.isViewingHistory &&
        chartType == ChartType.songs &&
        track != null &&
        !controller.isTrackInteractive(entry);

    // Songs and releases no longer in the library keep their verified
    // listening in every view; they show as heard, without playback
    // (SN-50 R1).
    final missingCurrentEntity = switch (chartType) {
      ChartType.songs => track == null,
      ChartType.albums => album == null,
    };

    final ChartEntryStatus? status = unavailableLiveTrack
        ? (track.isBlocked
              ? ChartEntryStatus.blacklisted
              : ChartEntryStatus.unavailable)
        : missingCurrentEntity
        ? ChartEntryStatus.historical
        : null;

    final VoidCallback? onTap = canInteract
        ? () {
            if (chartType == ChartType.songs && track != null) {
              unawaited(
                _showChartTrackContext(context, track, controller.entryTracks),
              );
              return;
            }

            if (chartType == ChartType.albums && album != null) {
              _openAlbum(context, album, editionId: presentation?.editionId);
            }
          }
        : null;

    final allTime = controller.allTimeChart;
    if (controller.isViewingAllTime && allTime != null) {
      final key = ValueKey<String>('charts-entry-${entry.entity.entityId}');
      final stats = allTime.statsFor(entry);
      final weeklyPeak = controller.weeklyPeakFor(entry);

      final compact = _isCompactRow(controller, entry);
      final cardKey = compact
          ? ValueKey<String>('charts-entry-card-${entry.entity.entityId}')
          : key;
      final card = entry.rank == 1
          ? AllTimeSpotlightCard(
              key: cardKey,
              entry: entry,
              chartType: chartType,
              stats: stats,
              artworkPath: artworkPath,
              status: status,
              weeklyPeakRank: weeklyPeak,
              longevity: longevity,
              title: presentation?.title ?? song?.title,
              subtitle: song?.subtitle,
              movement: controller.movementFor(entry),
              onTap: onTap,
            )
          : AllTimeEntryCard(
              key: cardKey,
              entry: entry,
              chartType: chartType,
              stats: stats,
              artworkPath: artworkPath,
              status: status,
              weeklyPeakRank: weeklyPeak,
              longevity: longevity,
              title: presentation?.title ?? song?.title,
              subtitle: song?.subtitle,
              movement: controller.movementFor(entry),
              onTap: onTap,
            );
      return _tiered(
        card: card,
        compact: compact,
        artworkPath: artworkPath,
        title: presentation?.title ?? song?.title ?? entry.entity.title,
        subtitle:
            song?.subtitle ?? ChartEntryCard.subtitleFor(entry, chartType),
        status: status,
        onTap: onTap,
      );
    }

    final compact = _isCompactRow(controller, entry);
    final id = entry.entity.entityId;
    final card = ChartEntryCard(
      key: ValueKey<String>(
        compact ? 'charts-entry-card-$id' : 'charts-entry-$id',
      ),
      entry: entry,
      chartType: chartType,
      artworkPath: artworkPath,
      status: status,
      longevity: longevity,
      previousExtendedRank: controller.previousExtendedRankFor(entry),
      bestSoFarRank: controller.bestSoFarRankFor(entry),
      weeklyPeakRank: controller.isViewingThisWeek
          ? controller.weeklyPeakFor(entry)
          : null,
      movement: controller.movementFor(entry),
      onTap: onTap,
    );

    return _tiered(
      card: card,
      compact: compact,
      artworkPath: artworkPath,
      title: presentation?.title ?? song?.title ?? entry.entity.title,
      subtitle: song?.subtitle ?? ChartEntryCard.subtitleFor(entry, chartType),
      status: status,
      onTap: onTap,
    );
  }

  /// Charts 2.0 C3 tiers: a featured #1, artwork-framed #2–10, and compact
  /// rows for #11–100 and Bubbling Under with the full card on expand.
  Widget _tiered({
    required Widget card,
    required bool compact,
    required String? artworkPath,
    required String title,
    required String subtitle,
    required ChartEntryStatus? status,
    required VoidCallback? onTap,
  }) {
    final id = entry.entity.entityId;
    if (compact) {
      return ChartCompactRow(
        key: ValueKey<String>('charts-entry-$id'),
        entry: entry,
        movement: controller.movementFor(entry),
        title: title,
        subtitle: subtitle,
        artworkPath: artworkPath,
        fallbackIcon: controller.chartType == ChartType.songs
            ? Icons.music_note_rounded
            : Icons.album_rounded,
        status: status,
        details: card,
        onTap: onTap,
      );
    }
    if (entry.rank == 1) {
      return ChartFeaturedFrame(
        chartName: ChartZoneNames.chart(controller.chartType),
        child: card,
      );
    }
    return ChartTopTenFrame(artworkPath: artworkPath, child: card);
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

/// [chartTracks] is the chart on screen, in rank order: Play queues the
/// chart from this song, so Previous and Next follow the standings.
Future<void> _showChartTrackContext(
  BuildContext context,
  LibraryTrack track,
  List<LibraryTrack> chartTracks,
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
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.creditLine} \u2022 ${track.albumDisplayTitle}',
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
                        unawaited(playback.playInContext(track, chartTracks));
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
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(showAddToPlaylistFlow(context, track));
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
                        initialEditionId: track.albumEditionId,
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

void _openAlbum(BuildContext context, LibraryAlbum album, {String? editionId}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumProfilePage(
        albumId: album.albumId,
        initialAlbumTitle: album.title,
        initialEditionId: editionId,
      ),
    ),
  );
}

bool _isCompactRow(ChartsController controller, ChartEntry entry) =>
    controller.board == ChartBoard.extended ||
    ChartRowTier.of(entry) == ChartRowTier.compact;

String _boardName(ChartType type, ChartBoard board) => switch ((type, board)) {
  (_, ChartBoard.top100) => ChartZoneNames.chart(type),
  (ChartType.songs, ChartBoard.extended) => ChartZoneNames.bubblingUnder,
  (ChartType.albums, ChartBoard.extended) =>
    '${ChartZoneNames.releases} #101–200',
};

/// Hot 100 | Bubbling Under (Albums & EPs: Top 100 | #101–200).
class _ChartBoardSelector extends StatelessWidget {
  const _ChartBoardSelector({required this.controller});

  final ChartsController controller;

  @override
  Widget build(BuildContext context) {
    final songs = controller.chartType == ChartType.songs;
    return SonusSegmentedSelector<ChartBoard>(
      key: const ValueKey<String>('charts-board-selector'),
      segments: [
        SonusSegment(
          value: ChartBoard.top100,
          icon: Icons.local_fire_department_rounded,
          label: songs ? 'Hot 100' : 'Top 100',
        ),
        SonusSegment(
          value: ChartBoard.extended,
          icon: Icons.bubble_chart_outlined,
          label: songs ? 'Bubbling Under' : '#101–200',
        ),
      ],
      selected: controller.board,
      onChanged: controller.selectBoard,
    );
  }
}

/// The built rows, by rank, so jump-to-rank can find one.
class _ChartRows {
  final Map<int, BuildContext> byRank = {};
}

class _RankAnchor extends StatefulWidget {
  const _RankAnchor({
    required this.rank,
    required this.rows,
    required this.child,
  });

  final int rank;
  final _ChartRows rows;
  final Widget child;

  @override
  State<_RankAnchor> createState() => _RankAnchorState();
}

class _RankAnchorState extends State<_RankAnchor> {
  @override
  Widget build(BuildContext context) {
    widget.rows.byRank[widget.rank] = context;
    return widget.child;
  }

  @override
  void dispose() {
    if (identical(widget.rows.byRank[widget.rank], context)) {
      widget.rows.byRank.remove(widget.rank);
    }
    super.dispose();
  }
}

/// A draggable scroll thumb for long boards (the fast-scroll rail). It
/// shows while scrolling only, so nothing stays on screen at rest.
class _ChartScrollRail extends StatelessWidget {
  const _ChartScrollRail({
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final ScrollController controller;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Scrollbar(
      key: const ValueKey<String>('charts-scroll-rail'),
      controller: controller,
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: child,
    );
  }
}

/// Asks for a position and scrolls to it (Charts 2.0 C3).
Future<void> _jumpToRank(
  BuildContext context, {
  required ScrollController scroll,
  required _ChartRows rows,
  required List<ChartEntry> entries,
}) async {
  if (entries.isEmpty) return;
  final first = entries.first.rank;
  final last = entries.last.rank;
  final rank = await showDialog<int>(
    context: context,
    builder: (context) => _JumpToRankDialog(first: first, last: last),
  );
  if (rank == null || !scroll.hasClients || !context.mounted) return;
  final target = entries.indexWhere((entry) => entry.rank >= rank);
  if (target < 0) return;
  final targetRank = entries[target].rank;
  final motion = SonusTheme.of(context).motion;

  // Rows are built lazily: step towards the row using the heights of the
  // rows already built, then bring it into view.
  for (var pass = 0; pass < 8; pass++) {
    final built = rows.byRank[targetRank];
    if (built != null && built.mounted) {
      await Scrollable.ensureVisible(
        built,
        alignment: 0.15,
        duration: motion.reduced ? Duration.zero : motion.medium,
        curve: motion.curve,
      );
      return;
    }
    final known = [
      for (final entry in rows.byRank.entries)
        if (entry.value.mounted && entry.value.findRenderObject() is RenderBox)
          entry,
    ];
    if (known.isEmpty) return;
    var heights = 0.0;
    for (final entry in known) {
      heights += (entry.value.findRenderObject()! as RenderBox).size.height;
    }
    final average = heights / known.length;
    known.sort((a, b) => a.key.compareTo(b.key));
    final anchor = targetRank < known.first.key ? known.first : known.last;
    final anchorIndex = entries.indexWhere((e) => e.rank == anchor.key);
    final delta = (target - anchorIndex) * average;
    final position = scroll.position;
    scroll.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
  }
}

class _JumpToRankDialog extends StatefulWidget {
  const _JumpToRankDialog({required this.first, required this.last});

  final int first;
  final int last;

  @override
  State<_JumpToRankDialog> createState() => _JumpToRankDialogState();
}

class _JumpToRankDialogState extends State<_JumpToRankDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_text.text.trim());
    if (value == null || value < widget.first || value > widget.last) {
      setState(
        () => _error = 'Enter a number from ${widget.first} to ${widget.last}',
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jump to position'),
      content: TextField(
        key: const ValueKey<String>('charts-jump-field'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          labelText: 'Position (${widget.first}–${widget.last})',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('charts-jump-go'),
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}
