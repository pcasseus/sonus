import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';
import 'sonus_news_story.dart';

/// The Sonus News Feed: an editorial view of real Chart Moments, separate
/// from the Hot 100 leaderboard. Filterable by edition; stories render as
/// featured, standard or compact cards.
class SonusNewsFeedView extends StatefulWidget {
  const SonusNewsFeedView({
    super.key,
    required this.stories,
    this.onRefresh,
    this.padding,
  });

  final List<SonusNewsStory> stories;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;

  @override
  State<SonusNewsFeedView> createState() => _SonusNewsFeedViewState();
}

class _SonusNewsFeedViewState extends State<SonusNewsFeedView> {
  /// Null shows every edition.
  SonusNewsEdition? _edition;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final gutter = tokens.metrics.pageGutter;
    final edition = _edition;
    final visible = edition == null
        ? widget.stories
        : widget.stories
              .where((story) => story.edition == edition)
              .toList(growable: false);

    final list = CustomScrollView(
      key: const PageStorageKey<String>('sonus-news-feed'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Masthead(
            selected: edition,
            counts: {
              for (final value in SonusNewsEdition.values)
                value: widget.stories
                    .where((story) => story.edition == value)
                    .length,
            },
            onSelected: (value) => setState(() => _edition = value),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: SonusStateView(
              key: const ValueKey<String>('sonus-news-empty'),
              icon: Icons.newspaper_rounded,
              title: widget.stories.isEmpty
                  ? 'No news yet'
                  : 'No ${edition?.label} stories yet',
              message:
                  'Stories appear as your weekly charts move and your '
                  'listening reaches milestones.',
            ),
          )
        else
          SliverPadding(
            padding:
                widget.padding ??
                EdgeInsets.fromLTRB(
                  gutter,
                  4,
                  gutter,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final story = visible[index];
                final card = switch (story.format) {
                  SonusNewsFormat.featured => _FeaturedStory(story: story),
                  SonusNewsFormat.standard => _StandardStory(story: story),
                  SonusNewsFormat.compact => _CompactStory(story: story),
                };

                return Padding(
                  key: ValueKey<String>('sonus-news-story-${story.id}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card,
                );
              },
            ),
          ),
      ],
    );

    final onRefresh = widget.onRefresh;
    return onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final SonusNewsEdition? selected;
  final Map<SonusNewsEdition, int> counts;
  final ValueChanged<SonusNewsEdition?> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final gutter = tokens.metrics.pageGutter;

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'Sonus News',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ),
          if (tokens.decoration.showMarks) ...[
            SizedBox(height: tokens.metrics.spaceXs),
            const SonusMotifMark(),
          ],
          const SizedBox(height: 6),
          Text(
            'Your charts and listening, reported. Weekly chart stories '
            'are separate from the all-time Hot 100.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const ValueKey<String>('sonus-news-edition-all'),
                label: const Text('All'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              for (final edition in SonusNewsEdition.values)
                ChoiceChip(
                  key: ValueKey<String>('sonus-news-edition-${edition.name}'),
                  label: Text('${edition.label} ${counts[edition] ?? 0}'),
                  selected: selected == edition,
                  onSelected: (_) => onSelected(edition),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edition, chart and date above a headline.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.story});

  final SonusNewsStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Text(
      '${story.edition.label.toUpperCase()} · ${story.kicker} · '
      '${_date(story.occurredAt)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.accentPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  static String _date(DateTime value) {
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
    final local = value.toLocal();
    return '${months[local.month - 1]} ${local.day}';
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.child, this.emphasis = false});

  final Widget child;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return Semantics(
      container: true,
      child: Material(
        color: emphasis ? colors.raisedSurface : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          side: BorderSide(
            color: emphasis && tokens.decoration.showMarks
                ? colors.accentPrimary
                : colors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _FeaturedStory extends StatelessWidget {
  const _FeaturedStory({required this.story});

  final SonusNewsStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return _StoryCard(
      emphasis: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            final size = wide
                ? 160.0
                : (constraints.maxWidth * 0.42).clamp(96.0, 160.0);
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Kicker(story: story),
                const SizedBox(height: 8),
                Text(
                  story.headline,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  story.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SonusArtworkImage(path: story.artworkPath, size: size),
                  const SizedBox(width: 18),
                  Expanded(child: text),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SonusArtworkImage(path: story.artworkPath, size: size),
                const SizedBox(height: 14),
                text,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StandardStory extends StatelessWidget {
  const _StandardStory({required this.story});

  final SonusNewsStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker(story: story),
        const SizedBox(height: 4),
        Text(
          story.headline,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          story.body,
          maxLines: largeText ? null : 3,
          overflow: largeText ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );

    return _StoryCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        // Artwork beside the text, or above it at large text sizes.
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SonusArtworkImage(path: story.artworkPath, size: 64),
                  const SizedBox(height: 10),
                  text,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SonusArtworkImage(path: story.artworkPath, size: 64),
                  const SizedBox(width: 14),
                  Expanded(child: text),
                ],
              ),
      ),
    );
  }
}

class _CompactStory extends StatelessWidget {
  const _CompactStory({required this.story});

  final SonusNewsStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return _StoryCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Kicker(story: story),
            const SizedBox(height: 3),
            Text(
              story.headline,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
