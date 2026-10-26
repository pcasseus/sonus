import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../domain/models/chart_type.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_publisher.dart';
import '../editorial/moment_visuals.dart';

/// One Moment as a social editorial post (SN-45): the publisher as author,
/// the story's headline and, when it adds a verified fact, a second
/// paragraph; pictures of exactly what the headline is about; real chart
/// badges; and links to the song, release and artist. There are no likes,
/// reposts, replies or view counts: Sonus never invents engagement.
class MomentPostCard extends StatelessWidget {
  const MomentPostCard({
    super.key,
    required this.story,
    required this.now,
    this.onOpenSong,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final MomentStory story;
  final DateTime now;
  final VoidCallback? onOpenSong;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final body = story.body;
    final tag = story.tag;
    final hasLinks =
        onOpenSong != null || onOpenAlbum != null || onOpenArtist != null;
    final facts = story.facts;
    final releaseName = facts.chartType == ChartType.albums
        ? facts.title
        : facts.album;

    // SN-49: one container per story, so a screen reader moves story by
    // story. The byline, headline and body are read as one item, the
    // picture's chart and status as another; the buttons stay separate
    // and say what they open.
    return Semantics(
      container: true,
      child: Material(
        key: ValueKey<String>('moment-post-${story.id}'),
        color: colors.raisedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius + 6),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MergeSemantics(
                key: ValueKey<String>('moment-post-story-${story.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Byline(
                      publisher: story.publisher,
                      occurredAt: story.occurredAt,
                      now: now,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      story.headline,
                      key: ValueKey<String>('moment-post-headline-${story.id}'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        body,
                        key: ValueKey<String>('moment-post-body-${story.id}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              MergeSemantics(child: _Collage(story: story)),
              if (hasLinks || tag != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (onOpenSong != null)
                      _LinkChip(
                        key: ValueKey<String>('moment-post-song-${story.id}'),
                        icon: Icons.music_note_rounded,
                        label: 'Song',
                        spokenLabel: 'Song options, ${facts.title}',
                        onPressed: onOpenSong!,
                      ),
                    if (onOpenAlbum != null)
                      _LinkChip(
                        key: ValueKey<String>('moment-post-album-${story.id}'),
                        icon: Icons.album_rounded,
                        label: facts.releaseLabel,
                        spokenLabel: releaseName == null
                            ? 'Open ${facts.releaseLabel}'
                            : 'Open ${facts.releaseLabel}, $releaseName',
                        onPressed: onOpenAlbum!,
                      ),
                    if (onOpenArtist != null)
                      _LinkChip(
                        key: ValueKey<String>('moment-post-artist-${story.id}'),
                        icon: Icons.person_rounded,
                        label: 'Artist',
                        spokenLabel: 'Open artist, ${facts.artist}',
                        onPressed: onOpenArtist!,
                      ),
                    if (tag != null)
                      MergeSemantics(
                        child: _Pill(
                          key: ValueKey<String>('moment-post-tag-${story.id}'),
                          label: tag,
                          background: colors.accentPrimary.withValues(
                            alpha: 0.14,
                          ),
                          foreground: colors.textPrimary,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({
    required this.publisher,
    required this.occurredAt,
    required this.now,
  });

  final MomentPublisher publisher;
  final DateTime occurredAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final handle = publisher.handle;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.accentPrimary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Icon(switch (publisher) {
            MomentPublisher.sonusDaily => Icons.newspaper_rounded,
            MomentPublisher.pulsePop => Icons.bolt_rounded,
          }, color: colors.accentPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                publisher.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Semantics(
                label:
                    '$handle, ${momentAgeLabel(occurredAt, now, long: true)}',
                excludeSemantics: true,
                child: Text(
                  '$handle · ${momentAgeLabel(occurredAt, now)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "now", "5m", "3h", "2d", or the date for older posts; [long] spells it
/// out for screen readers.
String momentAgeLabel(DateTime occurredAt, DateTime now, {bool long = false}) {
  final age = now.difference(occurredAt);
  String unit(int value, String short, String word) =>
      long ? '$value $word${value == 1 ? '' : 's'} ago' : '$value$short';

  if (age.inMinutes < 1) return long ? 'just now' : 'now';
  if (age.inHours < 1) return unit(age.inMinutes, 'm', 'minute');
  if (age.inDays < 1) return unit(age.inHours, 'h', 'hour');
  if (age.inDays < 7) return unit(age.inDays, 'd', 'day');

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = occurredAt.toLocal();
  final date = '${months[local.month - 1]} ${local.day}';
  return local.year == now.toLocal().year ? date : '$date, ${local.year}';
}

class _Collage extends StatelessWidget {
  const _Collage({required this.story});

  final MomentStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final visual = story.visual;
    final right = visual.right;
    final id = story.id;

    IconData iconFor(MomentImage image) => switch (image.kind) {
      MomentImageKind.cover => Icons.album_rounded,
      MomentImageKind.portrait => Icons.person_rounded,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: right == null ? 1.6 : 1.25,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CollageImage(
                    key: ValueKey<String>('moment-post-image-left-$id'),
                    path: visual.left.path,
                    icon: iconFor(visual.left),
                  ),
                ),
                if (right != null) ...[
                  ColoredBox(
                    color: colors.raisedSurface,
                    child: const SizedBox(width: 3),
                  ),
                  Expanded(
                    child: _CollageImage(
                      key: ValueKey<String>('moment-post-image-right-$id'),
                      path: right.path,
                      icon: iconFor(right),
                    ),
                  ),
                ],
              ],
            ),
            PositionedDirectional(
              top: 10,
              start: 10,
              end: 10,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Pill(
                  label: story.kicker.toUpperCase(),
                  icon: Icons.auto_awesome_rounded,
                  maxLines: 2,
                  background: colors.artworkScrim,
                  foreground: colors.onArtworkScrim,
                ),
              ),
            ),
            if (story.rank != null)
              PositionedDirectional(
                bottom: 10,
                start: 10,
                child: _RankBadge(rank: story.rank!),
              ),
            PositionedDirectional(
              bottom: 10,
              end: 10,
              child: _Pill(
                key: ValueKey<String>('moment-post-status-$id'),
                label: story.status,
                background: colors.artworkScrim,
                foreground: colors.onArtworkScrim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollageImage extends StatelessWidget {
  const _CollageImage({super.key, required this.path, required this.icon});

  final String? path;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final trimmed = path?.trim();
    final placeholder = SonusArtworkPlaceholder(icon: icon, iconSize: 40);

    if (trimmed == null || trimmed.isEmpty) return placeholder;

    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(trimmed),
        fit: BoxFit.cover,
        cacheWidth: constraints.maxWidth.isFinite
            ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round()
            : null,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.artworkScrim,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colors.onArtworkScrim,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.maxLines = 1,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    super.key,
    required this.icon,
    required this.label,
    required this.spokenLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;

  /// What a screen reader says: which song, release or artist it opens.
  final String spokenLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: colors.accentPrimary),
      label: Text(label, semanticsLabel: spokenLabel),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}
