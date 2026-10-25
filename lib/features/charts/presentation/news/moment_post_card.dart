import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import 'sonus_news_story.dart';

/// The badges on a Moment post, all read from the Moment itself.
class MomentPostBadges {
  const MomentPostBadges({required this.status, required this.tag, this.rank});

  factory MomentPostBadges.of(ChartMomentFeedItem item) {
    final dominant = item.events.firstWhere(
      (event) => event.eventType == item.dominantEventType,
    );
    final rank = dominant.currentRank;
    final threshold = dominant.threshold;

    final status = switch (item.dominantEventType) {
      ChartMomentEventType.firstNumberOne ||
      ChartMomentEventType.returnToNumberOne ||
      ChartMomentEventType.artistFirstNumberOneSong ||
      ChartMomentEventType.artistFirstNumberOneAlbum ||
      ChartMomentEventType.artistNthNumberOneSong ||
      ChartMomentEventType.artistNthNumberOneAlbum ||
      ChartMomentEventType.artistReturnsToNumberOneSong ||
      ChartMomentEventType.artistReturnsToNumberOneAlbum => 'NUMBER ONE',
      ChartMomentEventType.newPeak ||
      ChartMomentEventType.artistHighestChartingSong ||
      ChartMomentEventType.artistHighestChartingAlbum => 'NEW PEAK',
      ChartMomentEventType.peakMatch => 'PEAK MATCH',
      ChartMomentEventType.debut => 'DEBUT',
      ChartMomentEventType.reentry => 'RE-ENTRY',
      ChartMomentEventType.rankRise => 'CLIMBING',
      ChartMomentEventType.rankFall => 'FALLING',
      ChartMomentEventType.rankSame => 'STABLE',
      ChartMomentEventType.firstThresholdEntry ||
      ChartMomentEventType.thresholdReturn ||
      ChartMomentEventType.artistFirstThresholdSong ||
      ChartMomentEventType.artistFirstThresholdAlbum ||
      ChartMomentEventType.artistNthThresholdSong ||
      ChartMomentEventType.artistNthThresholdAlbum =>
        threshold == null ? 'BREAKTHROUGH' : 'TOP $threshold',
      ChartMomentEventType.artistSimultaneousThresholdSongs ||
      ChartMomentEventType.artistSimultaneousThresholdAlbums => 'RECORD',
      ChartMomentEventType.lifetimeStreamMilestone => 'MILESTONE',
      ChartMomentEventType.consecutiveWeeksMilestone ||
      ChartMomentEventType.totalWeeksMilestone ||
      ChartMomentEventType.consecutiveThresholdWeeksMilestone ||
      ChartMomentEventType.totalThresholdWeeksMilestone => 'LONGEVITY',
      ChartMomentEventType.losesNumberOne => 'LOSES #1',
      ChartMomentEventType.thresholdExit ||
      ChartMomentEventType.chartExit => 'EXIT',
    };

    final chart = item.isAllTime
        ? 'ALL-TIME'
        : switch (item.chartType) {
            ChartType.songs => 'HOT 100',
            ChartType.albums => 'TOP 200',
          };

    return MomentPostBadges(
      rank: rank,
      status: status,
      tag: rank == null ? chart : '$chart #$rank',
    );
  }

  final int? rank;
  final String status;

  /// For example "HOT 100 #11" or "ALL-TIME #3".
  final String tag;
}

/// One Moment as a social editorial post (SN-45): the edition as author,
/// the Moment's own copy, a collage of the artwork and the artist, real
/// chart badges, and links to the song, album and artist. There are no
/// likes, reposts or replies: Sonus never invents engagement.
class MomentPostCard extends StatelessWidget {
  const MomentPostCard({
    super.key,
    required this.story,
    required this.badges,
    required this.now,
    this.artistPortraitPath,
    this.onOpenSong,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  final SonusNewsStory story;
  final MomentPostBadges badges;
  final DateTime now;
  final String? artistPortraitPath;
  final VoidCallback? onOpenSong;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final hasLinks =
        onOpenSong != null || onOpenAlbum != null || onOpenArtist != null;

    return Material(
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
            _Byline(
              edition: story.edition,
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
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              story.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _Collage(
              storyId: story.id,
              artworkPath: story.artworkPath,
              portraitPath: artistPortraitPath,
              kicker: story.kicker,
              badges: badges,
            ),
            if (hasLinks) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onOpenSong != null)
                    _LinkChip(
                      key: ValueKey<String>('moment-post-song-${story.id}'),
                      icon: Icons.music_note_rounded,
                      label: 'Song',
                      onPressed: onOpenSong!,
                    ),
                  if (onOpenAlbum != null)
                    _LinkChip(
                      key: ValueKey<String>('moment-post-album-${story.id}'),
                      icon: Icons.album_rounded,
                      label: 'Album',
                      onPressed: onOpenAlbum!,
                    ),
                  if (onOpenArtist != null)
                    _LinkChip(
                      key: ValueKey<String>('moment-post-artist-${story.id}'),
                      icon: Icons.person_rounded,
                      label: 'Artist',
                      onPressed: onOpenArtist!,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _Pill(
                key: ValueKey<String>('moment-post-tag-${story.id}'),
                label: badges.tag,
                background: colors.accentPrimary.withValues(alpha: 0.14),
                foreground: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({
    required this.edition,
    required this.occurredAt,
    required this.now,
  });

  final SonusNewsEdition edition;
  final DateTime occurredAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final handle = switch (edition) {
      SonusNewsEdition.sonusDaily => '@sonusdaily',
      SonusNewsEdition.pulsePop => '@pulsepop',
    };

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
          child: Icon(switch (edition) {
            SonusNewsEdition.sonusDaily => Icons.newspaper_rounded,
            SonusNewsEdition.pulsePop => Icons.bolt_rounded,
          }, color: colors.accentPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                edition.label,
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
  const _Collage({
    required this.storyId,
    required this.artworkPath,
    required this.portraitPath,
    required this.kicker,
    required this.badges,
  });

  final String storyId;
  final String? artworkPath;
  final String? portraitPath;
  final String kicker;
  final MomentPostBadges badges;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final hasPortrait = portraitPath?.trim().isNotEmpty ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: hasPortrait ? 1.25 : 1.6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CollageImage(
                    key: ValueKey<String>('moment-post-artwork-$storyId'),
                    path: artworkPath,
                    icon: Icons.album_rounded,
                  ),
                ),
                if (hasPortrait) ...[
                  ColoredBox(
                    color: colors.raisedSurface,
                    child: const SizedBox(width: 3),
                  ),
                  Expanded(
                    child: _CollageImage(
                      key: ValueKey<String>('moment-post-portrait-$storyId'),
                      path: portraitPath,
                      icon: Icons.person_rounded,
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
                  label: kicker.toUpperCase(),
                  icon: Icons.auto_awesome_rounded,
                  maxLines: 2,
                  background: colors.artworkScrim,
                  foreground: colors.onArtworkScrim,
                ),
              ),
            ),
            if (badges.rank != null)
              PositionedDirectional(
                bottom: 10,
                start: 10,
                child: _RankBadge(rank: badges.rank!),
              ),
            PositionedDirectional(
              bottom: 10,
              end: 10,
              child: _Pill(
                key: ValueKey<String>('moment-post-status-$storyId'),
                label: badges.status,
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
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: colors.accentPrimary),
      label: Text(label),
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
