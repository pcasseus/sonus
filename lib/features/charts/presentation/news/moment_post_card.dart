import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../domain/models/chart_type.dart';
import '../editorial/moment_developing.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_publisher.dart';
import '../editorial/moment_visuals.dart';

/// One Moment as a social editorial post (SN-45): the publisher as author,
/// the story's headline and, when it adds a verified fact, a second
/// paragraph; pictures of exactly what the headline is about; real chart
/// badges, the chart named once (SN-50 F-Q22); and links to the song,
/// release and artist. There are no likes, reposts, replies or view
/// counts: Sonus never invents engagement.
class MomentPostCard extends StatelessWidget {
  const MomentPostCard({
    super.key,
    required this.story,
    required this.now,
    this.credit,
    this.onOpenSong,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final MomentStory story;
  final DateTime now;

  /// The song's role-aware performer line, as text only (F-Q19/F-Q20).
  final String? credit;
  final VoidCallback? onOpenSong;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final body = story.body;
    final credit = this.credit;
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
                    if (story.isDeveloping) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _Pill(
                          key: ValueKey<String>(
                            'moment-post-updated-${story.id}',
                          ),
                          label: 'UPDATED',
                          icon: Icons.update_rounded,
                          background: colors.accentPrimary.withValues(
                            alpha: 0.16,
                          ),
                          foreground: colors.textPrimary,
                        ),
                      ),
                    ],
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
                    if (credit != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        credit,
                        key: ValueKey<String>('moment-post-credit-${story.id}'),
                        semanticsLabel: 'Performers: $credit',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Charts 2.0 C1: nothing is drawn over the artwork; the
              // kicker, rank and status sit under it, read with it.
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Collage(story: story),
                    const SizedBox(height: 10),
                    _StoryMeta(story: story),
                  ],
                ),
              ),
              if (story.isDeveloping) ...[
                const SizedBox(height: 8),
                _UpdateThread(story: story),
              ],
              if (hasLinks) ...[
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

/// A developing story's thread: every climb it tells, newest first,
/// behind a button so the feed stays compact. No animation.
class _UpdateThread extends StatefulWidget {
  const _UpdateThread({required this.story});

  final MomentStory story;

  @override
  State<_UpdateThread> createState() => _UpdateThreadState();
}

class _UpdateThreadState extends State<_UpdateThread> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final story = widget.story;
    final updates = story.updates.reversed.toList();
    final count = updates.length;
    final localizations = MaterialLocalizations.of(context);

    String time(MomentStoryUpdate update) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(update.occurredAt.toLocal()),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: ValueKey<String>('moment-post-thread-${story.id}'),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            label: Text(_open ? 'Hide updates' : 'Show all $count updates'),
          ),
        ),
        if (_open)
          for (final (index, update) in updates.indexed)
            Padding(
              key: ValueKey<String>(
                'moment-post-update-${story.id}-${update.eventId}',
              ),
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Icon(
                      index == 0
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 12,
                      color: index == 0
                          ? colors.accentPrimary
                          : colors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time(update),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            update.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: index == 0
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
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

/// The story's kicker, chart rank and status, under the artwork.
class _StoryMeta extends StatelessWidget {
  const _StoryMeta({required this.story});

  final MomentStory story;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final id = story.id;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(
          key: ValueKey<String>('moment-post-kicker-$id'),
          label: story.kicker.toUpperCase(),
          icon: Icons.auto_awesome_rounded,
          maxLines: 2,
          background: colors.accentPrimary.withValues(alpha: 0.16),
          foreground: colors.textPrimary,
        ),
        if (story.rank != null) _RankBadge(rank: story.rank!),
        if (story.climb case final climb?)
          _ClimbBadge(
            key: ValueKey<String>('moment-post-climb-$id'),
            places: climb,
          ),
        _Pill(
          key: ValueKey<String>('moment-post-status-$id'),
          label: story.status,
          background: colors.surface,
          foreground: colors.textSecondary,
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// How many places the song climbed, beside the story rather than in it:
/// shown for every story with a comparable rise, so stories published
/// before their headlines named it show it too without changing words.
class _ClimbBadge extends StatelessWidget {
  const _ClimbBadge({super.key, required this.places});

  final int places;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final spoken = places == 1 ? 'Up 1 place' : 'Up $places places';

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colors.chartUp.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_upward_rounded, size: 14, color: colors.chartUp),
            const SizedBox(width: 2),
            Text(
              '$places',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.chartUp,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
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
