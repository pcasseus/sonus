import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_publisher.dart';
import '../editorial/moment_visuals.dart';
import 'moment_post_card.dart';
import 'moment_story_format.dart';

/// One story in the Moments feed (App Update 1.1), in the format its
/// significance calls for ([MomentStoryFormat]): a Feature Story, a Chart
/// Bulletin or a Milestone Spotlight. The whole card opens the expanded
/// story; nothing on it is decorative-only or invented (no likes, comments
/// or follower counts).
class MomentFeedCard extends StatelessWidget {
  const MomentFeedCard({
    super.key,
    required this.story,
    required this.now,
    this.onOpen,
    this.credit,
  });

  final MomentStory story;
  final DateTime now;
  final VoidCallback? onOpen;

  /// The song's role-aware performer line, as text (SN-50 F-Q19/F-Q20).
  final String? credit;

  @override
  Widget build(BuildContext context) {
    return switch (MomentStoryFormat.of(story)) {
      MomentStoryFormat.feature => MomentFeatureStoryCard(
        story: story,
        now: now,
        onOpen: onOpen,
        credit: credit,
      ),
      MomentStoryFormat.spotlight => MomentBulletinCard(
        story: story,
        now: now,
        onOpen: onOpen,
        spotlight: true,
        credit: credit,
      ),
      MomentStoryFormat.bulletin => MomentBulletinCard(
        story: story,
        now: now,
        onOpen: onOpen,
        credit: credit,
      ),
    };
  }
}

/// A major event: kind and byline, the story's two pictures side by side,
/// a large headline, its supporting fact and its badges.
class MomentFeatureStoryCard extends StatelessWidget {
  const MomentFeatureStoryCard({
    super.key,
    required this.story,
    required this.now,
    this.onOpen,
    this.credit,
  });

  final MomentStory story;
  final DateTime now;
  final VoidCallback? onOpen;
  final String? credit;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final palette = MomentEditorialPalette.of(colors, tokens.decoration);
    final radius = BorderRadius.circular(24);
    final body = story.body;

    return _StoryTapTarget(
      key: ValueKey<String>('moment-post-${story.id}'),
      story: story,
      onOpen: onOpen,
      radius: radius,
      decoration: palette.featureDecoration(radius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KindAndByline(story: story, now: now, palette: palette),
            const SizedBox(height: 12),
            _DualArtwork(story: story, height: 136),
            const SizedBox(height: 14),
            Text(
              story.headline,
              key: ValueKey<String>('moment-post-headline-${story.id}'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.2,
              ),
            ),
            _CreditLine(story: story, credit: credit),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body,
                key: ValueKey<String>('moment-post-body-${story.id}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
            MomentBadgeRow(story: story, palette: palette),
            _Developing(story: story),
          ],
        ),
      ),
    );
  }
}

/// An everyday story: artwork (or, for a spotlight, its number) beside the
/// kind, byline, headline and badges. Compact and scannable.
class MomentBulletinCard extends StatelessWidget {
  const MomentBulletinCard({
    super.key,
    required this.story,
    required this.now,
    this.onOpen,
    this.spotlight = false,
    this.credit,
  });

  final MomentStory story;
  final DateTime now;
  final VoidCallback? onOpen;
  final String? credit;

  /// A Milestone Spotlight: the number leads instead of the artwork.
  final bool spotlight;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final palette = MomentEditorialPalette.of(colors, tokens.decoration);
    final radius = BorderRadius.circular(18);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final number = spotlight ? MomentSpotlightNumber.of(story) : null;

    final media = number != null
        ? _SpotlightTile(story: story, number: number, palette: palette)
        : _SingleArtwork(image: _leadImage(story), size: 112);

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KindAndByline(story: story, now: now, palette: palette, compact: true),
        const SizedBox(height: 8),
        Text(
          story.headline,
          key: ValueKey<String>('moment-post-headline-${story.id}'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.28,
          ),
        ),
        _CreditLine(story: story, credit: credit),
        const SizedBox(height: 10),
        MomentBadgeRow(story: story, palette: palette),
        _Developing(story: story),
      ],
    );

    return _StoryTapTarget(
      key: ValueKey<String>('moment-post-${story.id}'),
      story: story,
      onOpen: onOpen,
      radius: radius,
      decoration: palette.bulletinDecoration(radius, spotlight: spotlight),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The editorial accent stripe.
            Container(
              width: 4,
              color: spotlight ? palette.purple : palette.pink,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 12),
                // Large text: the picture goes above the words, so the
                // headline keeps a readable measure.
                child: scale >= 1.3
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [media, const SizedBox(height: 10), text],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          media,
                          const SizedBox(width: 12),
                          Expanded(child: text),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static MomentImage _leadImage(MomentStory story) {
    final visual = story.visual;
    final right = visual.right;
    // A song's or release's own cover leads a bulletin; an artist story
    // shows the portrait.
    if (visual.left.kind == MomentImageKind.cover || right == null) {
      return visual.left;
    }
    return right.kind == MomentImageKind.cover ? right : visual.left;
  }
}

/// The performer line under a headline, as text only (SN-50 F-Q19/F-Q20).
class _CreditLine extends StatelessWidget {
  const _CreditLine({required this.story, required this.credit});

  final MomentStory story;
  final String? credit;

  @override
  Widget build(BuildContext context) {
    final credit = this.credit;
    if (credit == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        credit,
        key: ValueKey<String>('moment-post-credit-${story.id}'),
        semanticsLabel: 'Performers: $credit',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: SonusTheme.of(context).colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A developing story (SN-50): marked UPDATED, with its thread of updates
/// on request, exactly as before the redesign.
class _Developing extends StatelessWidget {
  const _Developing({required this.story});

  final MomentStory story;

  @override
  Widget build(BuildContext context) {
    if (!story.isDeveloping) return const SizedBox.shrink();
    final colors = SonusTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Semantics(
          label: 'UPDATED',
          excludeSemantics: true,
          child: Container(
            key: ValueKey<String>('moment-post-updated-${story.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: colors.accentPrimary.withValues(alpha: 0.16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.update_rounded, size: 14, color: colors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  'UPDATED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        MomentUpdateThread(story: story),
      ],
    );
  }
}

/// The badges under a story ([MomentBadge.of]).
class MomentBadgeRow extends StatelessWidget {
  const MomentBadgeRow({super.key, required this.story, required this.palette});

  final MomentStory story;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final badges = MomentBadge.of(story);
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: ValueKey<String>('moment-post-badges-${story.id}'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final badge in badges)
          MomentBadgeChip(badge: badge, palette: palette),
      ],
    );
  }
}

class MomentBadgeChip extends StatelessWidget {
  const MomentBadgeChip({
    super.key,
    required this.badge,
    required this.palette,
  });

  final MomentBadge badge;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final color = switch (badge.tone) {
      MomentBadgeTone.up => palette.up,
      MomentBadgeTone.down => palette.down,
      MomentBadgeTone.accent => palette.pinkText,
      MomentBadgeTone.gold => palette.gold,
      MomentBadgeTone.neutral => colors.textPrimary,
    };
    final border = palette.highContrast
        ? palette.outline
        : badge.tone == MomentBadgeTone.neutral
        ? colors.border
        : color;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge.icon != null) ...[
          Icon(badge.icon, size: 15, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            badge.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      label: badge.semantics ?? badge.label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: border,
            width: palette.highContrast ? 1.5 : 1,
          ),
          color: badge.tone == MomentBadgeTone.neutral || palette.highContrast
              ? null
              : color.withValues(alpha: 0.10),
        ),
        child: content,
      ),
    );
  }
}

/// The kind pill and the publisher byline: "✦ FEATURE STORY  ⚡ PulsePop · 2h".
class _KindAndByline extends StatelessWidget {
  const _KindAndByline({
    required this.story,
    required this.now,
    required this.palette,
    this.compact = false,
  });

  final MomentStory story;
  final DateTime now;
  final MomentEditorialPalette palette;

  /// A bulletin's smaller kind pill and byline, so both fit one line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final kind = MomentKind.of(story);
    final labelStyle = compact
        ? theme.textTheme.labelSmall?.copyWith(fontSize: 10.5)
        : theme.textTheme.labelMedium;
    final bylineStyle = compact
        ? theme.textTheme.labelMedium
        : theme.textTheme.labelLarge;
    final kindColor = palette.kindColor(kind);
    final age = momentAge(story.occurredAt, now);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          key: ValueKey<String>('moment-post-kind-${story.id}'),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 2 : 3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: palette.highContrast ? palette.outline : kindColor,
              width: palette.highContrast ? 1.5 : 1.2,
            ),
            color: palette.highContrast
                ? null
                : kindColor.withValues(alpha: 0.12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kind.icon, size: compact ? 12 : 14, color: kindColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  kind.label,
                  style: labelStyle?.copyWith(
                    color: kindColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label:
              '${story.publisher.label}, '
              '${momentAgeSpoken(story.occurredAt, now)}',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MomentPublisherMark(
                publisher: story.publisher,
                palette: palette,
                size: compact ? 15 : 18,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '${story.publisher.label} · $age',
                  key: ValueKey<String>('moment-post-byline-${story.id}'),
                  style: bylineStyle?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
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

/// A publisher's mark: PulsePop's bolt, Sonus Daily's front page.
class MomentPublisherMark extends StatelessWidget {
  const MomentPublisherMark({
    super.key,
    required this.publisher,
    required this.palette,
    this.size = 18,
  });

  final MomentPublisher publisher;
  final MomentEditorialPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = palette.publisherColor(publisher);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: palette.highContrast ? palette.outline : color,
          width: 1.2,
        ),
        color: palette.highContrast ? null : color.withValues(alpha: 0.16),
      ),
      child: Icon(
        publisher == MomentPublisher.pulsePop
            ? Icons.bolt_rounded
            : Icons.newspaper_rounded,
        size: size * 0.66,
        color: color,
      ),
    );
  }
}

/// The whole card as one button that opens the story.
class _StoryTapTarget extends StatelessWidget {
  const _StoryTapTarget({
    super.key,
    required this.story,
    required this.onOpen,
    required this.radius,
    required this.decoration,
    required this.child,
  });

  final MomentStory story;
  final VoidCallback? onOpen;
  final BorderRadius radius;
  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onOpen != null,
      hint: onOpen == null ? null : 'Opens the full story',
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey<String>('moment-post-open-${story.id}'),
            borderRadius: radius,
            onTap: onOpen,
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        ),
      ),
    );
  }
}

/// The story's two pictures side by side (the artist's portrait first, as
/// the approved design shows), each kept to what the headline names. One
/// picture fills the row when the other is missing; it is never duplicated.
class _DualArtwork extends StatelessWidget {
  const _DualArtwork({required this.story, required this.height});

  final MomentStory story;
  final double height;

  @override
  Widget build(BuildContext context) {
    final visual = story.visual;
    var first = visual.left;
    var second = visual.right;
    if (second != null &&
        second.kind == MomentImageKind.portrait &&
        first.kind == MomentImageKind.cover) {
      (first, second) = (second, first);
    }
    final images = [first, ?second].where((image) => image.hasImage).toList();
    final shown = images.isEmpty ? [visual.left] : images;

    return SizedBox(
      key: ValueKey<String>('moment-post-artwork-${story.id}'),
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              flex: shown.length == 2 && i == 0 ? 11 : 10,
              child: _ArtworkImage(
                key: ValueKey<String>(
                  'moment-post-image-${i == 0 ? 'left' : 'right'}-${story.id}',
                ),
                image: shown[i],
                radius: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SingleArtwork extends StatelessWidget {
  const _SingleArtwork({required this.image, required this.size});

  final MomentImage image;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: _ArtworkImage(image: image, radius: 12),
    );
  }
}

/// A Milestone Spotlight's number over the story's darkened artwork.
class _SpotlightTile extends StatelessWidget {
  const _SpotlightTile({
    required this.story,
    required this.number,
    required this.palette,
  });

  final MomentStory story;
  final MomentSpotlightNumber number;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final image = story.visual.left;
    final digits = Text(
      number.value,
      maxLines: 1,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: palette.gradients ? Colors.white : colors.textPrimary,
        height: 1,
      ),
    );
    return Semantics(
      label: '${number.value} ${number.unit.toLowerCase()}',
      excludeSemantics: true,
      child: SizedBox.square(
        key: ValueKey<String>('moment-post-spotlight-${story.id}'),
        dimension: 104,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image.hasImage && !palette.highContrast)
                Opacity(
                  opacity: 0.45,
                  child: _ArtworkImage(image: image, radius: 0),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.highContrast
                      ? palette.ink
                      : Colors.black.withValues(alpha: 0.45),
                  border: palette.highContrast
                      ? Border.all(color: palette.outline, width: 2)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      child: palette.gradients
                          ? ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [palette.pinkText, palette.purpleText],
                              ).createShader(bounds),
                              child: digits,
                            )
                          : digits,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(
                        number.unit,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: palette.highContrast
                              ? colors.textPrimary
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A library picture, or a quiet placeholder: never someone else's picture.
class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({super.key, required this.image, required this.radius});

  final MomentImage image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final placeholder = ColoredBox(
      color: colors.artworkPlaceholder,
      child: Center(
        child: Icon(
          image.kind == MomentImageKind.portrait
              ? Icons.person_rounded
              : Icons.album_rounded,
          color: colors.onArtworkPlaceholder,
          size: 32,
        ),
      ),
    );
    final path = image.path?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path == null || path.isEmpty
          ? placeholder
          : LayoutBuilder(
              builder: (context, constraints) {
                final ratio = MediaQuery.devicePixelRatioOf(context);
                final width = constraints.maxWidth.isFinite
                    ? (constraints.maxWidth * ratio).round()
                    : null;
                return Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: width,
                  // Portraits keep faces: aim slightly above centre.
                  alignment: image.kind == MomentImageKind.portrait
                      ? const Alignment(0, -0.35)
                      : Alignment.center,
                  errorBuilder: (_, _, _) => placeholder,
                  gaplessPlayback: true,
                );
              },
            ),
    );
  }
}

/// Exposed for the expanded story.
class MomentArtwork extends StatelessWidget {
  const MomentArtwork({super.key, required this.image, this.radius = 14});

  final MomentImage image;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      _ArtworkImage(image: image, radius: radius);
}
