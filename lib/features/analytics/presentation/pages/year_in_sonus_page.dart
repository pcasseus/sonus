import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('year-in-sonus-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          _YearHeader(
            year: controller.selectedYear,
            isCurrentYear: controller.selectedYear == controller.currentYear,
          ),
          const SizedBox(height: 18),
          _YearNavigator(controller: controller),
          const SizedBox(height: 22),

          if (controller.hasError) ...[
            _RefreshErrorBanner(onRetry: controller.refresh),
            const SizedBox(height: 16),
          ],

          if (!recap.hasListening)
            _EmptyYear(year: recap.year)
          else ...[
            _HeadlineSummary(recap: recap),
            const SizedBox(height: 28),
            _Highlights(recap: recap),
            const SizedBox(height: 28),
            _SonusSignature(recap: recap),
            const SizedBox(height: 28),
            _TopThree(data: controller.presentationData),
            const SizedBox(height: 28),
            _MonthlyTimeline(data: controller.presentationData, recap: recap),
            const SizedBox(height: 28),
            _Rankings(data: controller.presentationData),
          ],
        ],
      ),
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year, required this.isCurrentYear});

  final int year;
  final bool isCurrentYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey<String>('year-in-sonus-header'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SONUS',
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 2.4,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your $year in Sonus',
            key: const ValueKey<String>('year-in-sonus-title'),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isCurrentYear
                ? 'Your listening story so far.'
                : 'The music that defined your year.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _YearNavigator extends StatelessWidget {
  const _YearNavigator({required this.controller});

  final YearInSonusController controller;

  @override
  Widget build(BuildContext context) {
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
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
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
        Row(
          children: [
            Expanded(
              child: _BigMetric(
                label: 'STREAMS',
                value: _formatInt(summary.qualifiedStreamCount),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigMetric(
                label: 'LISTENING',
                value: _formatDuration(recap.audibleListeningDuration),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SmallMetric(
                label: 'TRACKS',
                value: summary.distinctSongCount,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallMetric(
                label: 'ARTISTS',
                value: summary.distinctArtistCount,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallMetric(
                label: 'ALBUMS',
                value: summary.distinctAlbumCount,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.3,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          children: [
            Text(
              _formatInt(value),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Your year at a glance',
          subtitle: 'A few things that made this year yours.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HighlightCard(
              icon: Icons.calendar_month_rounded,
              label: 'Most active month',
              value: activeMonth == null
                  ? '—'
                  : _monthName(activeMonth.month.month),
              detail: activeMonth == null
                  ? 'No qualified streams'
                  : '${_formatInt(activeMonth.streams)} streams',
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
                  : '${_formatInt(peakDay.qualifiedStreamCount)} streams',
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
    final theme = Theme.of(context);

    return SizedBox(
      width: 165,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Your Sonus signature',
          subtitle: 'A few patterns hidden inside your year.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'The ones at #1',
          subtitle: 'Your top artist, track, and album.',
        ),
        const SizedBox(height: 12),
        if (artist != null)
          _ChampionCard(
            icon: Icons.person_rounded,
            label: '#1 ARTIST',
            title: artist.name,
            subtitle: '${_formatInt(artist.streams)} streams',
            artworkPath: artist.artworkPath,
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
                '${track.artistName} • ${_formatInt(track.streams)} streams',
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
                '${album.artistName} • ${_formatInt(album.streams)} streams',
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
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Artwork(path: artworkPath, fallbackIcon: icon, size: 70),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded),
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
    final maxStreams = recap.months.fold<int>(
      0,
      (current, month) => month.streams > current ? month.streams : current,
    );

    return Column(
      key: const ValueKey<String>('year-in-sonus-timeline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'January ? December',
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
  });

  final YearInSonusMonthRow? row;
  final int month;
  final int streams;
  final Duration listeningDuration;
  final int maxStreams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = maxStreams == 0 ? 0.0 : streams / maxStreams;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                _monthShortName(month),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(minHeight: 9, value: progress),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 54,
              child: Text(
                _formatInt(streams),
                textAlign: TextAlign.end,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (streams > 0 && row != null) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Text(
              [
                if (row!.topSongTitle != null) 'Song: ${row!.topSongTitle}',
                if (row!.topArtistName != null) 'Artist: ${row!.topArtistName}',
                if (listeningDuration > Duration.zero)
                  'Listening: ${_formatDuration(listeningDuration)}',
              ].join('  •  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ArtistRankings(rows: current.artists),
        const SizedBox(height: 28),
        _TrackRankings(rows: current.tracks),
        const SizedBox(height: 28),
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
            subtitle: '${_formatInt(row.streams)} streams',
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.person_rounded,
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
            subtitle: '${row.artistName} • ${_formatInt(row.streams)} streams',
            artworkPath: row.artworkPath,
            fallbackIcon: Icons.music_note_rounded,
            onTap: row.canPlay ? () => _playTrack(context, row) : null,
            trailing: row.hasCurrentLibraryEntity && !row.canPlay
                ? const Icon(Icons.block_rounded, size: 18)
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
            subtitle: '${row.artistName} • ${_formatInt(row.streams)} streams',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Text(emptyMessage)
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1) const Divider(height: 1),
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
  });

  final int rank;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final IconData fallbackIcon;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          _Artwork(path: artworkPath, fallbackIcon: fallbackIcon, size: 46),
        ],
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.path,
    required this.fallbackIcon,
    required this.size,
  });

  final String? path;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = path?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: SizedBox(
        width: size,
        height: size,
        child: normalized == null || normalized.isEmpty
            ? _fallback(context)
            : Image.file(
                File(normalized),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return _fallback(context);
                },
              ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(fallbackIcon, color: theme.colorScheme.primary),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _EmptyYear extends StatelessWidget {
  const _EmptyYear({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('year-in-sonus-empty'),
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 54),
          const SizedBox(height: 16),
          Text(
            'No listening story for $year yet',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Qualified listening in Sonus will build your annual recap.',
            textAlign: TextAlign.center,
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
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: const Icon(Icons.error_outline_rounded),
        title: const Text('Could not refresh Year in Sonus'),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
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
