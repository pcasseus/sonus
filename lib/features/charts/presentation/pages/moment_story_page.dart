import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../application/models/chart_moment_feed_item.dart';
import '../../domain/moments/chart_moment_scope.dart';
import '../../application/services/moment_chart_journey_service.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/services/all_time_history_replay.dart';
import '../editorial/moment_editorial_desk.dart';
import '../editorial/moment_family.dart';
import '../editorial/moment_visuals.dart';
import '../news/moment_feed_cards.dart';
import '../news/moment_story_format.dart';

/// A song, release or artist the story is about, as a working link.
class MomentRelatedLink {
  const MomentRelatedLink({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.onOpen,
  });

  /// "Song", "Album", "EP" or "Artist".
  final String kind;
  final String title;
  final String subtitle;
  final MomentImage image;
  final VoidCallback onOpen;
}

/// The expanded story (App Update 1.1): the full headline, publisher and
/// time, the story's pictures, its recorded facts, a verified chart journey
/// and its related music. Every number is recorded or replayed from stored
/// qualified plays; anything not known is left out or said to be
/// unavailable, never estimated.
class MomentStoryPage extends StatefulWidget {
  const MomentStoryPage({
    super.key,
    required this.story,
    required this.now,
    this.journey,
    this.related = const [],
  });

  final MomentStory story;
  final DateTime now;

  /// Loads the subject's chart journey; none for artist stories.
  final MomentJourneyLoader? journey;
  final List<MomentRelatedLink> related;

  /// Completed days the journey shows.
  static const int journeyDays = 7;

  @override
  State<MomentStoryPage> createState() => _MomentStoryPageState();
}

class _MomentStoryPageState extends State<MomentStoryPage> {
  Future<MomentChartJourney?>? _journey;

  /// Why this story has no Chart Journey, or null when it has one. Day-by-
  /// day ranks are reconstructed only for the all-time charts (from the
  /// stored qualified plays); a weekly story never borrows them, and an
  /// artist story has no chart position to follow.
  String? get _unavailableReason {
    final story = widget.story;
    final item = story.item;
    final chart = item.chartType == ChartType.albums
        ? 'Sonus Albums & EPs'
        : 'Sonus Hot 100';
    if (story.family.name.startsWith('artist') ||
        item.subjectType == ChartMomentFeedSubjectType.artist) {
      return 'Chart journeys follow songs and releases; this story is about '
          'an artist.';
    }
    if (item.scope != ChartMomentScope.allTime) {
      return 'This story is from the weekly $chart. Day-by-day ranks are '
          'kept only for the all-time $chart, so no journey is shown here.';
    }
    return null;
  }

  bool get _hasSubjectChart => _unavailableReason == null;

  @override
  void initState() {
    super.initState();
    final loader = widget.journey;
    if (loader != null && _hasSubjectChart) {
      _journey = loader(
        widget.story.item.chartType,
        widget.story.item.entity.entityId,
      ).catchError((Object _) => null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final palette = MomentEditorialPalette.of(colors, tokens.decoration);
    final story = widget.story;
    final body = story.body;
    final kind = MomentKind.of(story);

    return Scaffold(
      key: ValueKey<String>('moment-story-page-${story.id}'),
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(),
      ),
      body: FutureBuilder<MomentChartJourney?>(
        future: _journey,
        builder: (context, snapshot) {
          final journey = snapshot.data;
          final loading =
              _journey != null &&
              snapshot.connectionState != ConnectionState.done;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _Hero(story: story, palette: palette, kind: kind),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  story.headline,
                  key: ValueKey<String>('moment-story-headline-${story.id}'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _PublisherRow(story: story, now: widget.now, palette: palette),
              if (body != null) ...[
                const SizedBox(height: 14),
                Text(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _StatTiles(story: story, journey: journey, palette: palette),
              if (_journey != null ||
                  (widget.journey != null && _unavailableReason != null)) ...[
                const SizedBox(height: 16),
                _JourneyCard(
                  story: story,
                  journey: journey,
                  loading: loading,
                  palette: palette,
                  unavailableReason: _unavailableReason,
                ),
                if (journey != null) ...[
                  const SizedBox(height: 16),
                  _FactsCard(story: story, journey: journey),
                ],
              ],
              if (story.updates.length > 1) ...[
                const SizedBox(height: 20),
                _Updates(story: story, now: widget.now),
              ],
              if (widget.related.isNotEmpty) ...[
                const SizedBox(height: 22),
                Semantics(
                  header: true,
                  child: Text(
                    'Related',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _RelatedRow(links: widget.related, palette: palette),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.story, required this.palette, required this.kind});

  final MomentStory story;
  final MomentEditorialPalette palette;
  final MomentKind kind;

  /// The pill over a faded hero needs gradients; High contrast, Low effects
  /// and Decoration off keep it below the pictures, on the page.
  bool get overlay => palette.gradients && !palette.highContrast;

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
    final images = [first, ?second].where((i) => i.hasImage).toList();
    final shown = images.isEmpty ? [visual.left] : images;
    final width = MediaQuery.sizeOf(context).width;
    final height = math.min(280.0, width * 0.70);
    final background = SonusTheme.of(context).colors.background;
    final artwork = SizedBox(
      key: ValueKey<String>('moment-story-artwork-${story.id}'),
      height: height,
      child: Row(
        // The pictures fill the hero's height (cover-cropped), so the fade
        // and the kind pill sit on them, not in empty space below.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              flex: shown.length == 2 && i == 0 ? 11 : 10,
              child: MomentArtwork(image: shown[i], radius: 18),
            ),
          ],
        ],
      ),
    );
    if (!overlay) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          artwork,
          const SizedBox(height: 14),
          _KindPill(kind: kind, palette: palette),
        ],
      );
    }
    // The pictures fade into the page and carry the kind pill, so the
    // artwork, badge and headline read as one composition (approved
    // hybrid). The fade covers only the lower edge of the pictures.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: -24,
          left: -16,
          right: -16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.9,
                colors: [
                  palette.purple.withValues(alpha: 0.22),
                  palette.pink.withValues(alpha: 0.06),
                  background.withValues(alpha: 0),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        artwork,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: height * 0.42,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: 0),
                    background.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: 12,
          bottom: 12,
          child: _KindPill(kind: kind, palette: palette, solid: true),
        ),
      ],
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.kind,
    required this.palette,
    this.solid = false,
  });

  final MomentKind kind;
  final MomentEditorialPalette palette;

  /// Over the hero: an ink backing keeps the label readable on any artwork.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final color = palette.kindColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: palette.highContrast ? palette.outline : color,
          width: 1.5,
        ),
        color: palette.highContrast
            ? null
            : solid
            ? Color.alphaBlend(color.withValues(alpha: 0.16), palette.ink)
            : color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              kind.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublisherRow extends StatelessWidget {
  const _PublisherRow({
    required this.story,
    required this.now,
    required this.palette,
  });

  final MomentStory story;
  final DateTime now;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          MomentPublisherMark(
            publisher: story.publisher,
            palette: palette,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.publisher.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  momentAgeSpoken(story.occurredAt, now),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Current rank, movement and a third recorded fact (days at #1, or the
/// peak). A tile with nothing recorded is left out.
class _StatTiles extends StatelessWidget {
  const _StatTiles({
    required this.story,
    required this.journey,
    required this.palette,
  });

  final MomentStory story;
  final MomentChartJourney? journey;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final first = story.item.events.first;
    final rank = story.rank;
    final tiles = <Widget>[];
    if (rank != null) {
      tiles.add(_Tile(value: '#$rank', label: 'Current Rank'));
    }
    final climb = story.climb;
    final previous = first.previousRank;
    final current = first.currentRank;
    if (climb != null && climb > 0) {
      tiles.add(
        _Tile(
          value: '$climb',
          label: 'Movement',
          icon: Icons.arrow_upward_rounded,
          color: palette.up,
          spoken: 'Up $climb',
        ),
      );
    } else if (previous != null && current != null && current > previous) {
      tiles.add(
        _Tile(
          value: '${current - previous}',
          label: 'Movement',
          icon: Icons.arrow_downward_rounded,
          color: palette.down,
          spoken: 'Down ${current - previous}',
        ),
      );
    }
    final hold =
        story.family == MomentFamily.songNumberOneHold ||
        story.family == MomentFamily.releaseNumberOneHold;
    final daysAtOne = hold
        ? first.milestoneValue
        : journey?.totals.numberOneDays;
    if (daysAtOne != null && daysAtOne > 0) {
      tiles.add(
        _Tile(
          value: '$daysAtOne',
          label: hold ? 'Days at #1 in a row' : 'Days at #1',
          icon: Icons.workspace_premium_rounded,
          color: palette.gold,
        ),
      );
    } else if (journey?.peakRank != null) {
      tiles.add(_Tile(value: '#${journey!.peakRank}', label: 'Peak'));
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale >= 1.3) {
      return Column(
        key: ValueKey<String>('moment-story-stats-${story.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tile in tiles) ...[tile, const SizedBox(height: 8)],
        ],
      );
    }
    return IntrinsicHeight(
      key: ValueKey<String>('moment-story-stats-${story.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.spoken,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final palette = MomentEditorialPalette.of(colors, tokens.decoration);
    return Semantics(
      label: '$label: ${spoken ?? value}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: palette.panelDecoration(
          BorderRadius.circular(16),
          lift: 0.12,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: color ?? colors.textPrimary, size: 26),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color ?? colors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The verified chart journey: the rank at the close of each of the last
/// completed days. A day off the chart is a gap, never a guessed point.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.story,
    required this.journey,
    required this.loading,
    required this.palette,
    this.unavailableReason,
  });

  final MomentStory story;
  final MomentChartJourney? journey;
  final bool loading;
  final MomentEditorialPalette palette;

  /// Set when no journey on this story's own chart can be reconstructed.
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final journey = this.journey;
    final days = journey?.recent(MomentStoryPage.journeyDays) ?? const [];
    final chartName = story.item.chartType == ChartType.albums
        ? 'Sonus Albums & EPs'
        : 'Sonus Hot 100';

    Widget content;
    final reason = unavailableReason;
    if (reason != null) {
      content = Padding(
        key: ValueKey<String>('moment-story-journey-unavailable-${story.id}'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          reason,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    } else if (loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (journey == null || !journey.hasJourney) {
      content = Padding(
        key: ValueKey<String>('moment-story-journey-unavailable-${story.id}'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'The chart journey appears once this has finished two chart days '
          'on the $chartName.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    } else {
      content = Semantics(
        label: [
          for (final day in days)
            '${_date(day.dayStartLocal)}: '
                '${day.rank == null ? 'off the chart' : '#${day.rank}'}',
        ].join(', '),
        excludeSemantics: true,
        child: _JourneyChart(
          key: ValueKey<String>('moment-story-journey-${story.id}'),
          days: days,
          palette: palette,
          textColor: colors.textPrimary,
          labelColor: colors.textSecondary,
          gridColor: colors.divider,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: palette.panelDecoration(BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Chart Journey',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (reason == null) ...[
            const SizedBox(height: 4),
            Text(
              'Rank at the close of each completed day, all-time $chartName.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }
}

class _JourneyChart extends StatelessWidget {
  const _JourneyChart({
    super.key,
    required this.days,
    required this.palette,
    required this.textColor,
    required this.labelColor,
    required this.gridColor,
  });

  final List<ChartDayStanding> days;
  final MomentEditorialPalette palette;
  final Color textColor;
  final Color labelColor;
  final Color gridColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rankStyle = theme.textTheme.labelLarge?.copyWith(
      color: textColor,
      fontWeight: FontWeight.w800,
    );
    final dateStyle = theme.textTheme.labelSmall?.copyWith(color: labelColor);
    return Column(
      children: [
        SizedBox(
          height: 96,
          child: CustomPaint(
            size: Size.infinite,
            painter: _JourneyPainter(
              ranks: [for (final day in days) day.rank],
              line: palette.highContrast ? textColor : palette.pink,
              point: palette.highContrast ? textColor : palette.pinkText,
              grid: gridColor,
              glow: palette.glow,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Column(
                  children: [
                    FittedBox(
                      child: Text(
                        day.rank == null ? '—' : '#${day.rank}',
                        style: rankStyle,
                      ),
                    ),
                    FittedBox(
                      child: Text(_date(day.dayStartLocal), style: dateStyle),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _JourneyPainter extends CustomPainter {
  _JourneyPainter({
    required this.ranks,
    required this.line,
    required this.point,
    required this.grid,
    required this.glow,
  });

  final List<int?> ranks;
  final Color line;
  final Color point;
  final Color grid;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final known = ranks.whereType<int>().toList();
    if (known.isEmpty) return;
    final best = known.reduce(math.min);
    final worst = known.reduce(math.max);
    final columns = ranks.length;
    final step = size.width / columns;
    const pad = 10.0;
    double y(int rank) => worst == best
        ? size.height / 2
        : pad + (rank - best) / (worst - best) * (size.height - pad * 2);
    Offset at(int index, int rank) => Offset(step * (index + 0.5), y(rank));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      gridPaint,
    );

    final paint = Paint()
      ..color = line
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Only consecutive known days are joined: a gap stays a gap.
    for (var i = 1; i < columns; i++) {
      final a = ranks[i - 1];
      final b = ranks[i];
      if (a == null || b == null) continue;
      canvas.drawLine(at(i - 1, a), at(i, b), paint);
    }
    final dot = Paint()..color = point;
    final halo = Paint()..color = point.withValues(alpha: 0.25);
    for (var i = 0; i < columns; i++) {
      final rank = ranks[i];
      if (rank == null) continue;
      if (glow) canvas.drawCircle(at(i, rank), 9, halo);
      canvas.drawCircle(at(i, rank), 5, dot);
    }
  }

  @override
  bool shouldRepaint(_JourneyPainter old) =>
      old.ranks != ranks || old.line != line || old.point != point;
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.story, required this.journey});

  final MomentStory story;
  final MomentChartJourney journey;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final songs = story.item.chartType == ChartType.songs;
    final totals = journey.totals;
    final rows = <(IconData, String, String)>[
      (
        Icons.leaderboard_rounded,
        'Chart',
        songs ? 'Sonus Hot 100' : 'Sonus Albums & EPs',
      ),
      if (journey.peakRank != null)
        (Icons.north_rounded, 'Peak', '#${journey.peakRank}'),
      if (journey.firstChartedAt != null)
        (
          Icons.event_rounded,
          'First Entry',
          _longDate(journey.firstChartedAt!.toLocal()),
        ),
      (Icons.bar_chart_rounded, 'Total Days on Chart', '${totals.chartDays}'),
      if (songs && totals.hot100Days > 0)
        (
          Icons.local_fire_department_rounded,
          'Days on Hot 100',
          '${totals.hot100Days}',
        ),
      if (totals.numberOneDays > 0)
        (
          Icons.workspace_premium_rounded,
          'Days at #1',
          '${totals.numberOneDays}',
        ),
      if (totals.longestNumberOneRun > 1)
        (
          Icons.timeline_rounded,
          'Longest run at #1',
          '${totals.longestNumberOneRun} days',
        ),
    ];
    final theme = Theme.of(context);
    return Container(
      key: ValueKey<String>('moment-story-facts-${story.id}'),
      decoration: MomentEditorialPalette.of(
        colors,
        tokens.decoration,
      ).panelDecoration(BorderRadius.circular(18), lift: 0.06),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.divider),
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(rows[i].$1, size: 20, color: colors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rows[i].$3,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Days count completed chart days (local midnight), from '
              '${journey.days.isEmpty ? 'its first day' : _longDate(journey.days.first.dayStartLocal)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Updates extends StatelessWidget {
  const _Updates({required this.story, required this.now});

  final MomentStory story;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final updates = story.updates.reversed.toList();
    return Column(
      key: ValueKey<String>('moment-story-updates-${story.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Story updates',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final update in updates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    momentAge(update.occurredAt, now),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    update.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
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

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.links, required this.palette});

  final List<MomentRelatedLink> links;
  final MomentEditorialPalette palette;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    Widget card(MomentRelatedLink link) {
      final artist = link.kind == 'Artist';
      return Semantics(
        button: true,
        label: 'Open ${link.kind.toLowerCase()}, ${link.title}',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: palette.panelDecoration(
              BorderRadius.circular(18),
              lift: artist ? 0.22 : 0.08,
            ),
            child: InkWell(
              key: ValueKey<String>('moment-story-related-${link.kind}'),
              borderRadius: BorderRadius.circular(18),
              onTap: link.onOpen,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.square(
                      dimension: links.length > 2 ? 72 : 88,
                      child: MomentArtwork(
                        image: link.image,
                        radius: artist ? 44 : 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      link.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
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

    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale >= 1.3 || links.length > 3) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final link in links)
            SizedBox(
              width: scale >= 1.3 ? double.infinity : 160,
              child: card(link),
            ),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: card(links[i])),
          ],
        ],
      ),
    );
  }
}

const _months = [
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

String _date(DateTime local) => '${_months[local.month - 1]} ${local.day}';

String _longDate(DateTime local) =>
    '${_months[local.month - 1]} ${local.day}, ${local.year}';

/// Opens [story] as its own page.
Future<void> openMomentStory(
  BuildContext context, {
  required MomentStory story,
  required DateTime now,
  MomentJourneyLoader? journey,
  List<MomentRelatedLink> related = const [],
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MomentStoryPage(
        story: story,
        now: now,
        journey: journey,
        related: related,
      ),
    ),
  );
}
