import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../../core/design/widgets/sonus_metric_tile.dart';
import '../../application/models/year_in_sonus/year_in_sonus_album_row.dart';
import '../../application/models/year_in_sonus/year_in_sonus_artist_row.dart';
import '../../application/models/year_in_sonus/year_in_sonus_month_row.dart';
import '../../application/models/year_in_sonus/year_in_sonus_presentation_data.dart';
import '../../application/models/year_in_sonus/year_in_sonus_recap.dart';
import '../../application/models/year_in_sonus/year_in_sonus_track_row.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../controllers/year_in_sonus_controller.dart';

/// The annual recap as vertically scrolling editorial chapters. Every
/// figure comes from the recap; nothing is animated.
class YearInSonusPage extends StatelessWidget {
  const YearInSonusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<YearInSonusController?>();

    if (controller == null) {
      return const _YearMessage(
        key: ValueKey<String>('year-in-sonus-initializing'),
        icon: Icons.auto_awesome_rounded,
        title: 'Year in Sonus is getting ready',
        message: 'Your annual listening story is still initializing.',
      );
    }

    final recap = controller.recap;

    if (controller.isLoading && recap == null) {
      return const Center(
        key: ValueKey<String>('year-in-sonus-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (controller.hasError && recap == null) {
      return _YearMessage(
        key: const ValueKey<String>('year-in-sonus-error'),
        icon: Icons.error_outline_rounded,
        title: 'Year in Sonus could not be loaded',
        message: 'Try loading your annual listening story again.',
        action: FilledButton.icon(
          onPressed: () {
            unawaited(controller.load());
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (recap == null) {
      return const _YearMessage(
        icon: Icons.auto_awesome_rounded,
        title: 'No annual recap available',
        message: 'Start listening in Sonus to build your yearly story.',
      );
    }

    final gutter = SonusTheme.of(context).metrics.pageGutter;
    const chapterGap = SizedBox(height: 34);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('year-in-sonus-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 40),
        children: [
          _YearCover(
            year: controller.selectedYear,
            isCurrentYear: controller.selectedYear == controller.currentYear,
          ),
          const SizedBox(height: 14),
          _YearNavigator(controller: controller),
          const SizedBox(height: 20),

          if (controller.hasError) ...[
            _RefreshErrorBanner(onRetry: controller.refresh),
            const SizedBox(height: 16),
          ],

          if (!recap.hasListening)
            _EmptyYear(year: recap.year)
          else ...[
            _HeadlineSummary(recap: recap),
            chapterGap,
            _Highlights(recap: recap),
            const SizedBox(height: 22),
            _SonusSignature(recap: recap),
            chapterGap,
            _TopThree(data: controller.presentationData),
            chapterGap,
            _MonthlyTimeline(data: controller.presentationData, recap: recap),
            chapterGap,
            _Rankings(data: controller.presentationData),
          ],
        ],
      ),
    );
  }
}

/// The recap's cover: raised surface, theme texture and motif, and an
/// accent rule. Decoration follows the user's intensity setting.
class _YearCover extends StatelessWidget {
  const _YearCover({required this.year, required this.isCurrentYear});

  final int year;
  final bool isCurrentYear;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.cardRadius * 1.6);

    return ClipRRect(
      key: const ValueKey<String>('year-in-sonus-header'),
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.raisedSurface,
          border: Border.all(color: colors.divider),
          borderRadius: radius,
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: SonusSurfaceTexture()),
            if (tokens.decoration.showMarks)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ColoredBox(
                  color: colors.accentPrimary,
                  child: const SizedBox(width: 6),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 24, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SONUS',
                    style: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w900,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      'Your $year in Sonus',
                      key: const ValueKey<String>('year-in-sonus-title'),
                      style: tokens.text.pageTitle.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                  if (tokens.decoration.showMarks) ...[
                    SizedBox(height: tokens.metrics.spaceSm),
                    const SonusMotifMark(width: 72, height: 12),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    isCurrentYear
                        ? 'Your listening story so far.'
                        : 'The music that defined your year.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
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

class _YearNavigator extends StatelessWidget {
  const _YearNavigator({required this.controller});

  final YearInSonusController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Row(
      key: const ValueKey<String>('year-in-sonus-year-navigation'),
      children: [
        IconButton(
          key: const ValueKey<String>('year-in-sonus-previous-year'),
          tooltip: 'Previous year',
          onPressed: () {
            unawaited(controller.previousYear());
          },
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            '${controller.selectedYear}',
            key: const ValueKey<String>('year-in-sonus-year-label'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: tokens.colors.textPrimary,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('year-in-sonus-next-year'),
          tooltip: 'Next year',
          onPressed: controller.canGoNext
              ? () {
                  unawaited(controller.nextYear());
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// A chapter heading: a small chapter number, a motif heading and an
/// optional subtitle.
class _ChapterTitle extends StatelessWidget {
  const _ChapterTitle({required this.title, this.chapter, this.subtitle});

  final String title;

  /// Two-digit chapter number, e.g. "01"; null for sub-sections.
  final String? chapter;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);
    final chapter = this.chapter;
    final subtitle = this.subtitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapter != null)
          ExcludeSemantics(
            child: Text(
              'CHAPTER $chapter',
              style: theme.textTheme.labelSmall?.copyWith(
                color: tokens.colors.textSecondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ),
        if (chapter != null) const SizedBox(height: 4),
        SonusSectionHeading(title: title),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Equal-width tiles whose column count follows the text-scaled width.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.columnsAtWidth});

  final List<Widget> tiles;
  final int Function(double effectiveWidth) columnsAtWidth;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = columnsAtWidth(constraints.maxWidth / scale);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

int _twoUp(double effectiveWidth) => effectiveWidth >= 300 ? 2 : 1;

int _threeUp(double effectiveWidth) => effectiveWidth >= 360
    ? 3
    : effectiveWidth >= 240
    ? 2
    : 1;

class _HeadlineSummary extends StatelessWidget {
  const _HeadlineSummary({required this.recap});

  final YearInSonusRecap recap;

  @override
  Widget build(BuildContext context) {
    final summary = recap.summary;

    return Column(
      key: const ValueKey<String>('year-in-sonus-headline-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(chapter: '01', title: 'Your year in numbers'),
        const SizedBox(height: 14),
        _TileGrid(
          columnsAtWidth: _twoUp,
          tiles: [
            SonusMetricTile(
              label: 'Streams',
              value: _formatInt(summary.qualifiedStreamCount),
              featured: true,
            ),
            SonusMetricTile(
              label: 'Listening',
              value: _formatDuration(recap.audibleListeningDuration),
              featured: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TileGrid(
          columnsAtWidth: _threeUp,
          tiles: [
            SonusMetricTile(
              label: 'Tracks',
              value: _formatInt(summary.distinctSongCount),
            ),
            SonusMetricTile(
              label: 'Artists',
              value: _formatInt(summary.distinctArtistCount),
            ),
            SonusMetricTile(
              label: 'Albums',
              value: _formatInt(summary.distinctAlbumCount),
            ),
          ],
        ),
      ],
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.recap});

  final YearInSonusRecap recap;

  @override
  Widget build(BuildContext context) {
    final activeMonth = recap.mostActiveMonth;
    final peakDay = recap.behavior.peakDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(
          chapter: '02',
          title: 'Milestones',
          subtitle: 'A few things that made this year yours.',
        ),
        const SizedBox(height: 14),
        _TileGrid(
          columnsAtWidth: _twoUp,
          tiles: [
            _HighlightCard(
              icon: Icons.calendar_month_rounded,
              label: 'Most active month',
              value: activeMonth == null
                  ? '—'
                  : _monthName(activeMonth.month.month),
              detail: activeMonth == null
                  ? 'No qualified streams'
                  : '${_formatInt(activeMonth.streams)} ${sonusCountNoun(activeMonth.streams, 'stream')}',
            ),
            _HighlightCard(
              icon: Icons.local_fire_department_rounded,
              label: 'Longest streak',
              value: '${recap.longestListeningStreakDays}',
              detail: recap.longestListeningStreakDays == 1
                  ? 'consecutive day'
                  : 'consecutive days',
            ),
            _HighlightCard(
              icon: Icons.explore_rounded,
              label: 'New artists',
              value: _formatInt(recap.newArtistCount),
              detail: 'first heard this year',
            ),
            _HighlightCard(
              icon: Icons.album_rounded,
              label: 'New albums',
              value: _formatInt(recap.newAlbumCount),
              detail: 'first heard this year',
            ),
            _HighlightCard(
              icon: Icons.bolt_rounded,
              label: 'Most active day',
              value: peakDay == null
                  ? '—'
                  : _formatShortDate(peakDay.localDate),
              detail: peakDay == null
                  ? 'No qualified streams'
                  : '${_formatInt(peakDay.qualifiedStreamCount)} ${sonusCountNoun(peakDay.qualifiedStreamCount, 'stream')}',
            ),
            _HighlightCard(
              icon: Icons.today_rounded,
              label: 'Active days',
              value: _formatInt(recap.behavior.activeQualifiedDayCount),
              detail: 'days with qualified listening',
            ),
          ],
        ),
      ],
    );
  }
}

/// A milestone: accent icon, label, large tabular value and a detail line,
/// read as one sentence by screen readers.
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      child: MergeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.divider),
            borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, color: colors.accentPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: tokens.text.numeric.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SonusSignature extends StatelessWidget {
  const _SonusSignature({required this.recap});

  final YearInSonusRecap recap;

  @override
  Widget build(BuildContext context) {
    final trackShare = recap.topTrackStreamShare;
    final artistShare = recap.topArtistStreamShare;
    final breadth = recap.tracksPerArtist;

    if (trackShare == null && artistShare == null && breadth == null) {
      return const SizedBox.shrink();
    }

    return Column(
      key: const ValueKey<String>('year-in-sonus-signature'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(
          title: 'Your Sonus signature',
          subtitle: 'A few patterns hidden inside your year.',
        ),
        const SizedBox(height: 14),
        _TileGrid(
          columnsAtWidth: _twoUp,
          tiles: [
            if (trackShare != null)
              _HighlightCard(
                icon: Icons.repeat_rounded,
                label: 'Favorite-track share',
                value: _formatPercent(trackShare),
                detail: 'of all yearly streams',
              ),
            if (artistShare != null)
              _HighlightCard(
                icon: Icons.person_pin_rounded,
                label: 'Favorite-artist share',
                value: _formatPercent(artistShare),
                detail: 'of all yearly streams',
              ),
            if (breadth != null)
              _HighlightCard(
                icon: Icons.hub_rounded,
                label: 'Tracks per artist',
                value: breadth.toStringAsFixed(1),
                detail: 'your listening breadth',
              ),
          ],
        ),
      ],
    );
  }
}

class _TopThree extends StatelessWidget {
  const _TopThree({required this.data});

  final YearInSonusPresentationData? data;

  @override
  Widget build(BuildContext context) {
    final current = data;

    if (current == null) {
      return const SizedBox.shrink();
    }

    final artist = current.artists.isEmpty ? null : current.artists.first;
    final track = current.tracks.isEmpty ? null : current.tracks.first;
    final album = current.albums.isEmpty ? null : current.albums.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(
          chapter: '03',
          title: 'The ones at #1',
          subtitle: 'Your top artist, track, and album.',
        ),
        const SizedBox(height: 14),
        if (artist != null)
          _ChampionCard(
            icon: Icons.person_rounded,
            label: '#1 ARTIST',
            title: artist.name,
            subtitle:
                '${_formatInt(artist.streams)} ${sonusCountNoun(artist.streams, 'stream')}',
            artworkPath: artist.artworkPath,
            circularArtwork: true,
            onTap: artist.hasCurrentLibraryEntity
                ? () => _openArtist(context, artist)
                : null,
          ),
        if (artist != null && track != null) const SizedBox(height: 10),
        if (track != null)
          _ChampionCard(
            icon: Icons.music_note_rounded,
            label: '#1 TRACK',
            title: track.title,
            subtitle:
                '${track.artistName} • ${_formatInt(track.streams)} ${sonusCountNoun(track.streams, 'stream')}',
            artworkPath: track.artworkPath,
            onTap: track.canPlay ? () => _playTrack(context, track) : null,
          ),
        if (track != null && album != null) const SizedBox(height: 10),
        if (album != null)
          _ChampionCard(
            icon: Icons.album_rounded,
            label: '#1 ALBUM',
            title: album.title,
            subtitle:
                '${album.artistName} • ${_formatInt(album.streams)} ${sonusCountNoun(album.streams, 'stream')}',
            artworkPath: album.artworkPath,
            onTap: album.hasCurrentLibraryEntity
                ? () => _openAlbum(context, album)
                : null,
          ),
      ],
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    required this.onTap,
    this.circularArtwork = false,
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final VoidCallback? onTap;
  final bool circularArtwork;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    return Material(
      color: colors.raisedSurface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Artwork(
                path: artworkPath,
                fallbackIcon: icon,
                size: 84,
                circular: circularArtwork,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w900,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.sectionHeading.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyTimeline extends StatelessWidget {
  const _MonthlyTimeline({required this.data, required this.recap});

  final YearInSonusPresentationData? data;
  final YearInSonusRecap recap;

  @override
  Widget build(BuildContext context) {
    final rows = data?.months;
    final peak = recap.mostActiveMonth;
    final maxStreams = recap.months.fold<int>(
      0,
      (current, month) => month.streams > current ? month.streams : current,
    );

    return Column(
      key: const ValueKey<String>('year-in-sonus-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(
          chapter: '04',
          title: 'January–December',
          subtitle: 'How your listening moved through the year.',
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < recap.months.length; index++) ...[
          _MonthTimelineRow(
            row: rows != null && index < rows.length ? rows[index] : null,
            month: recap.months[index].month.month,
            streams: recap.months[index].streams,
            listeningDuration: recap.months[index].listeningDuration,
            maxStreams: maxStreams,
            isPeak: peak != null && recap.months[index].month == peak.month,
          ),
          if (index != recap.months.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MonthTimelineRow extends StatelessWidget {
  const _MonthTimelineRow({
    required this.row,
    required this.month,
    required this.streams,
    required this.listeningDuration,
    required this.maxStreams,
    required this.isPeak,
  });

  final YearInSonusMonthRow? row;
  final int month;
  final int streams;
  final Duration listeningDuration;
  final int maxStreams;

  /// The most active month, marked with a word as well as the accent.
  final bool isPeak;

  /// Text scale above which the row stacks, as in the shared data tables.
  static const double _largeTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final progress = maxStreams == 0 ? 0.0 : streams / maxStreams;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Above 1.3x text the month, count and PEAK badge share one line and the
    // bar spans the row beneath, so "Jan" never wraps and the bar keeps its
    // width. Below that, the label column scales with the text.
    final textScaler = MediaQuery.textScalerOf(context);
    final stacked = textScaler.scale(1) > _largeTextScale;
    final labelWidth = stacked ? 0.0 : textScaler.scale(46);

    final label = Text(
      _monthShortName(month),
      maxLines: 1,
      softWrap: false,
      style: labelStyle,
    );
    final bar = ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          minHeight: 10,
          value: progress,
          color: isPeak
              ? colors.accentPrimary
              : Color.lerp(colors.surface, colors.accentPrimary, 0.6),
          backgroundColor: colors.progressInactive,
        ),
      ),
    );
    final value = Text(
      _formatInt(streams),
      textAlign: TextAlign.end,
      style: labelStyle,
    );
    final peak = [
      if (isPeak) ...[
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.accentPrimary),
            borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              'PEAK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    ];

    return Semantics(
      container: true,
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              Row(
                children: [
                  Expanded(child: label),
                  value,
                  ...peak,
                ],
              ),
              const SizedBox(height: 6),
              bar,
            ] else
              Row(
                children: [
                  SizedBox(width: labelWidth, child: label),
                  Expanded(child: bar),
                  const SizedBox(width: 12),
                  value,
                  ...peak,
                ],
              ),
            if (streams > 0 && row != null) ...[
              const SizedBox(height: 5),
              Padding(
                padding: EdgeInsets.only(left: labelWidth),
                child: Text(
                  [
                    if (row!.topSongTitle != null) 'Song: ${row!.topSongTitle}',
                    if (row!.topArtistName != null)
                      'Artist: ${row!.topArtistName}',
                    if (listeningDuration > Duration.zero)
                      'Listening: ${_formatDuration(listeningDuration)}',
                  ].join('  •  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Rankings extends StatelessWidget {
  const _Rankings({required this.data});

  final YearInSonusPresentationData? data;

  @override
  Widget build(BuildContext context) {
    final current = data;

    if (current == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ChapterTitle(chapter: '05', title: 'Top lists'),
        const SizedBox(height: 16),
        _ArtistRankings(rows: current.artists),
        const SizedBox(height: 26),
        _TrackRankings(rows: current.tracks),
        const SizedBox(height: 26),
        _AlbumRankings(rows: current.albums),
      ],
    );
  }
}

class _ArtistRankings extends StatelessWidget {
  const _ArtistRankings({required this.rows});

  final List<YearInSonusArtistRow> rows;

  @override
  Widget build(BuildContext context) {
    return _RankingSection(
      title: 'Top 10 Artists',
      emptyMessage: 'No artists ranked this year.',
      children: [
        for (final row in rows)
          _RankingTile(
            rank: row.rank,
            title: row.name,
            subtitle:
                '${_formatInt(row.streams)} ${sonusCountNoun(row.streams, 'stream')}',
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.person_rounded,
            circularArtwork: true,
            onTap: row.hasCurrentLibraryEntity
                ? () => _openArtist(context, row)
                : null,
          ),
      ],
    );
  }
}

class _TrackRankings extends StatelessWidget {
  const _TrackRankings({required this.rows});

  final List<YearInSonusTrackRow> rows;

  @override
  Widget build(BuildContext context) {
    return _RankingSection(
      title: 'Top 25 Tracks',
      emptyMessage: 'No tracks ranked this year.',
      children: [
        for (final row in rows)
          _RankingTile(
            rank: row.rank,
            title: row.title,
            subtitle:
                '${row.artistName} • ${_formatInt(row.streams)} ${sonusCountNoun(row.streams, 'stream')}',
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.music_note_rounded,
            onTap: row.canPlay ? () => _playTrack(context, row) : null,
            trailing: row.hasCurrentLibraryEntity && !row.canPlay
                ? Icon(
                    Icons.block_rounded,
                    size: 18,
                    semanticLabel: 'Unavailable',
                    color: SonusTheme.of(context).colors.textSecondary,
                  )
                : null,
          ),
      ],
    );
  }
}

class _AlbumRankings extends StatelessWidget {
  const _AlbumRankings({required this.rows});

  final List<YearInSonusAlbumRow> rows;

  @override
  Widget build(BuildContext context) {
    return _RankingSection(
      title: 'Top 10 Albums',
      emptyMessage: 'No albums ranked this year.',
      children: [
        for (final row in rows)
          _RankingTile(
            rank: row.rank,
            title: row.title,
            subtitle:
                '${row.artistName} • ${_formatInt(row.streams)} ${sonusCountNoun(row.streams, 'stream')}',
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.album_rounded,
            onTap: row.hasCurrentLibraryEntity
                ? () => _openAlbum(context, row)
                : null,
          ),
      ],
    );
  }
}

class _RankingSection extends StatelessWidget {
  const _RankingSection({
    required this.title,
    required this.emptyMessage,
    required this.children,
  });

  final String title;
  final String emptyMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Text(
            emptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          )
        else
          // A Material, not a coloured box, so the tiles' ink stays visible.
          Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
              side: BorderSide(color: colors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    Divider(height: 1, color: colors.divider),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    required this.fallbackIcon,
    required this.onTap,
    this.trailing,
    this.circularArtwork = false,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final IconData fallbackIcon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool circularArtwork;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Artwork(
            path: artworkPath,
            fallbackIcon: fallbackIcon,
            size: 46,
            circular: circularArtwork,
          ),
        ],
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: colors.textSecondary)),
    );
  }
}

/// Artwork decoded at its display size, framed by the theme.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.path,
    required this.fallbackIcon,
    required this.size,
    this.circular = false,
  });

  final String? path;
  final IconData fallbackIcon;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final normalized = path?.trim();
    final fallback = SonusArtworkPlaceholder(
      icon: fallbackIcon,
      iconSize: size * 0.42,
    );
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return SonusArtworkFrame(
      size: size,
      circular: circular,
      child: normalized == null || normalized.isEmpty
          ? fallback
          : Image.file(
              File(normalized),
              fit: BoxFit.cover,
              cacheWidth: decodeSize,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _EmptyYear extends StatelessWidget {
  const _EmptyYear({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Padding(
      key: const ValueKey<String>('year-in-sonus-empty'),
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 54,
            color: colors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No listening story for $year yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Qualified listening in Sonus will build your annual recap.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      child: ListTile(
        leading: Icon(
          Icons.error_outline_rounded,
          color: scheme.onErrorContainer,
        ),
        title: Text(
          'Could not refresh Year in Sonus',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: TextButton(
          onPressed: () {
            unawaited(onRetry());
          },
          child: const Text('Retry'),
        ),
      ),
    );
  }
}

class _YearMessage extends StatelessWidget {
  const _YearMessage({
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
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

Future<void> _playTrack(BuildContext context, YearInSonusTrackRow row) async {
  final track = row.track;
  final playback = context.read<PlaybackCoordinator?>();

  if (track == null || playback == null || !row.canPlay) {
    return;
  }

  try {
    await playback.playTrack(track);
  } catch (_) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not play this track.')));
  }
}

void _openArtist(BuildContext context, YearInSonusArtistRow row) {
  if (!row.hasCurrentLibraryEntity) {
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArtistProfilePage(
        artistId: row.entityId,
        initialArtistName: row.name,
      ),
    ),
  );
}

void _openAlbum(BuildContext context, YearInSonusAlbumRow row) {
  if (!row.hasCurrentLibraryEntity) {
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          AlbumProfilePage(albumId: row.entityId, initialAlbumTitle: row.title),
    ),
  );
}

String _formatPercent(double value) {
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours == 0) {
    return '${duration.inMinutes}m';
  }

  if (minutes == 0) {
    return '${hours}h';
  }

  return '${hours}h ${minutes}m';
}

String _formatInt(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(digits[index]);
  }

  return buffer.toString();
}

String _formatShortDate(DateTime date) {
  return '${_monthShortName(date.month)} ${date.day}';
}

String _monthName(int month) {
  const months = [
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
  ];

  return months[month - 1];
}

String _monthShortName(int month) {
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

  return months[month - 1];
}
