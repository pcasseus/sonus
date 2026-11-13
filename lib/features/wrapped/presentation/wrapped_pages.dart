import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/sonus_theme.dart';
import '../../../core/design/widgets/sonus_bar_strip.dart';
import '../../../core/design/widgets/sonus_state_view.dart';
import '../../../core/design/widgets/sonus_surface_card.dart';
import '../../analytics/application/models/pulse/pulse_period.dart';
import '../application/wrapped_summary.dart';
import 'wrapped_controller.dart';
import 'wrapped_format.dart';
import 'wrapped_scope.dart';

/// Opens Sonus Wrapped with its own route-level scope.
Future<void> openSonusWrapped(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const WrappedScope(child: WrappedLandingPage()),
      ),
    );

/// Every year and month with recorded listening, newest first.
class WrappedLandingPage extends StatelessWidget {
  const WrappedLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WrappedController?>();
    return Scaffold(
      key: const ValueKey<String>('wrapped-landing'),
      appBar: AppBar(title: const Text('Sonus Wrapped')),
      body: switch (controller) {
        null => const SonusStateView(
          icon: Icons.auto_awesome_outlined,
          title: 'Sonus Wrapped isn\'t available',
          message: 'Your library isn\'t ready yet.',
        ),
        final c when !c.archiveLoaded => const SonusStateView.loading(),
        final c when c.archiveFailed => const SonusStateView(
          icon: Icons.error_outline,
          title: 'Sonus Wrapped couldn\'t load',
          message: 'Your listening history is safe. Try again later.',
          isError: true,
        ),
        final c when c.archive.isEmpty => const SonusStateView(
          icon: Icons.auto_awesome_outlined,
          title: 'No listening yet',
          message:
              'Sonus Wrapped is made from the music you play in Sonus. '
              'Listen for a while and your first month will appear here.',
        ),
        final c => _Archive(controller: c),
      },
    );
  }
}

class _Archive extends StatelessWidget {
  const _Archive({required this.controller});

  final WrappedController controller;

  @override
  Widget build(BuildContext context) {
    final archive = controller.archive;
    final start = archive.historyStartLocal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (start != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Your Sonus listening history starts on '
              '${WrappedFormat.day(start)}. Wrapped counts only what Sonus '
              'recorded.',
              key: const ValueKey<String>('wrapped-history-start'),
            ),
          ),
        _SectionTitle('Years'),
        for (final year in archive.years)
          _PeriodTile(
            key: ValueKey<String>('wrapped-year-${year.year}'),
            period: year,
          ),
        const SizedBox(height: 16),
        _SectionTitle('Months'),
        for (final month in archive.months)
          _PeriodTile(
            key: ValueKey<String>('wrapped-month-${month.year}-${month.month}'),
            period: month,
          ),
      ],
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({super.key, required this.period});

  final PulsePeriod period;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final running =
        !now.isBefore(period.startLocal) && now.isBefore(period.endLocal);
    return ListTile(
      title: Text(WrappedFormat.period(period)),
      subtitle: running ? const Text('In progress') : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _push(context, WrappedPeriodPage(period: period)),
    );
  }
}

void _push(BuildContext context, Widget page) {
  final controller = context.read<WrappedController?>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<WrappedController?>.value(
        value: controller,
        child: page,
      ),
    ),
  );
}

/// Loads [period]'s summary and builds [builder] with it, with honest
/// loading, error and empty states.
class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.period, required this.builder});

  final PulsePeriod period;
  final Widget Function(BuildContext context, WrappedSummary summary) builder;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WrappedController?>();
    if (controller == null) {
      return const SonusStateView(
        icon: Icons.auto_awesome_outlined,
        title: 'Sonus Wrapped isn\'t available',
      );
    }
    return FutureBuilder<WrappedSummary>(
      key: ValueKey<int>(controller.generation),
      future: controller.summary(period),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SonusStateView(
            icon: Icons.error_outline,
            title: 'This summary couldn\'t load',
            message: 'Your listening history is safe. Try again later.',
            isError: true,
          );
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const SonusStateView.loading();
        }
        return builder(context, summary);
      },
    );
  }
}

/// A month's or year's Wrapped: totals, highlights and links to the full
/// lists. Arrows move to the neighbouring month or year.
class WrappedPeriodPage extends StatefulWidget {
  const WrappedPeriodPage({super.key, required this.period});

  final PulsePeriod period;

  @override
  State<WrappedPeriodPage> createState() => _WrappedPeriodPageState();
}

class _WrappedPeriodPageState extends State<WrappedPeriodPage> {
  late PulsePeriod _period = widget.period;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WrappedController?>();
    final archive = controller?.archive;
    final periods = archive == null
        ? const <PulsePeriod>[]
        : _period.kind == PulsePeriodKind.year
        ? archive.years
        : archive.months;
    final index = periods.indexOf(_period);
    // Newest first: "previous" is later in the list.
    final older = index >= 0 && index + 1 < periods.length
        ? periods[index + 1]
        : null;
    final newer = index > 0 ? periods[index - 1] : null;
    return Scaffold(
      key: const ValueKey<String>('wrapped-period'),
      appBar: AppBar(
        title: Text(WrappedFormat.period(_period)),
        actions: [
          IconButton(
            key: const ValueKey<String>('wrapped-older'),
            tooltip: 'Earlier',
            onPressed: older == null
                ? null
                : () => setState(() => _period = older),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const ValueKey<String>('wrapped-newer'),
            tooltip: 'Later',
            onPressed: newer == null
                ? null
                : () => setState(() => _period = newer),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: _SummaryView(
        period: _period,
        builder: (context, summary) => _Overview(summary: summary),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.summary});

  final WrappedSummary summary;

  @override
  Widget build(BuildContext context) {
    final note = WrappedFormat.stateNote(summary);
    final totals = summary.totals;
    final comparison = summary.comparison;
    final previous = comparison.totals;
    final period = summary.period;
    return ListView(
      key: ValueKey<String>('wrapped-overview-${period.year}-${period.month}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(note, key: const ValueKey<String>('wrapped-note')),
          ),
        if (!summary.hasListening)
          const SonusSurfaceCard(
            child: Text(
              'No streams were recorded in this period.',
              key: ValueKey<String>('wrapped-empty'),
            ),
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Stat('Streams', '${totals.streams}', 'wrapped-streams'),
              _Stat(
                'Listening time',
                WrappedFormat.time(totals.listened),
                'wrapped-time',
              ),
              _Stat('Songs', '${totals.songs}', 'wrapped-songs'),
              _Stat('Artists', '${totals.artists}', 'wrapped-artists'),
              _Stat('Albums & EPs', '${totals.albums}', 'wrapped-albums'),
              _Stat('Active days', '${totals.activeDays}', 'wrapped-days'),
            ],
          ),
          const SizedBox(height: 16),
          if (comparison.isAvailable && previous != null)
            _Card(
              title:
                  'Compared with ${WrappedFormat.period(comparison.previous)}',
              keyName: 'wrapped-comparison',
              children: [
                Text(
                  WrappedFormat.change(
                    totals.streams,
                    previous.streams,
                    'streams',
                    comparison.previous,
                  ),
                ),
                Text(
                  WrappedFormat.change(
                    totals.listened.inMinutes,
                    previous.listened.inMinutes,
                    'minutes',
                    comparison.previous,
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'No comparison: ${WrappedFormat.period(comparison.previous)} '
                'isn\'t fully covered by your listening history.',
                key: const ValueKey<String>('wrapped-no-comparison'),
              ),
            ),
          _Card(
            title: 'Highlights',
            keyName: 'wrapped-highlights',
            children: [
              if (summary.mostPlayedSong case final song?)
                Text(
                  'Most-played song: ${song.title} '
                  '(${WrappedFormat.streams(song.streams)})',
                ),
              if (summary.mostPlayedArtist case final artist?)
                Text(
                  'Most-played artist: ${artist.title} '
                  '(${WrappedFormat.streams(artist.streams)})',
                ),
              if (summary.mostActiveMonth case final month?)
                Text(
                  'Most active month: '
                  '${WrappedFormat.monthName(month.period.month)} '
                  '(${WrappedFormat.streams(month.totals.streams)})',
                ),
              for (final milestone in summary.milestones)
                Text(WrappedFormat.milestone(milestone)),
            ],
          ),
          if (summary.chartWeeks > 0)
            _Card(
              title: 'Sonus Hot 100',
              keyName: 'wrapped-charts',
              children: [
                Text(
                  '${summary.chartWeeks} finalized '
                  '${summary.chartWeeks == 1 ? 'week' : 'weeks'} ended in '
                  '${WrappedFormat.period(period)}.',
                ),
                for (final leader in summary.chartNumberOnes)
                  Text(
                    '#1: ${leader.title} by ${leader.artistName} '
                    '(${leader.weeks} ${leader.weeks == 1 ? 'week' : 'weeks'})',
                  ),
              ],
            ),
          const SizedBox(height: 8),
          _Link('Top songs', 'wrapped-open-songs', () {
            _push(
              context,
              WrappedRankingPage(
                title: 'Top songs',
                period: period,
                select: (s) => s.topSongs,
              ),
            );
          }),
          _Link('Top artists', 'wrapped-open-artists', () {
            _push(
              context,
              WrappedRankingPage(
                title: 'Top artists',
                period: period,
                select: (s) => s.topArtists,
              ),
            );
          }),
          _Link('Top albums & EPs', 'wrapped-open-albums', () {
            _push(
              context,
              WrappedRankingPage(
                title: 'Top albums & EPs',
                period: period,
                select: (s) => s.topAlbums,
              ),
            );
          }),
          _Link('Genres', 'wrapped-open-genres', () {
            _push(context, WrappedGenresPage(period: period));
          }),
          _Link('Listening over time', 'wrapped-open-activity', () {
            _push(context, WrappedActivityPage(period: period));
          }),
          if (period.kind == PulsePeriodKind.year)
            _Link('Month by month', 'wrapped-open-months', () {
              _push(context, WrappedMonthsPage(period: period));
            }),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.keyName);

  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: SonusSurfaceCard(
        padding: const EdgeInsets.all(14),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                value,
                key: ValueKey<String>(keyName),
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.keyName,
    required this.children,
  });

  final String title;
  final String keyName;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SonusSurfaceCard(
      key: ValueKey<String>(keyName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          for (final child in children)
            Padding(padding: const EdgeInsets.only(top: 6), child: child),
        ],
      ),
    ),
  );
}

class _Link extends StatelessWidget {
  const _Link(this.title, this.keyName, this.onTap);

  final String title;
  final String keyName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey<String>(keyName),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// A top-ten list of the period.
class WrappedRankingPage extends StatelessWidget {
  const WrappedRankingPage({
    super.key,
    required this.title,
    required this.period,
    required this.select,
  });

  final String title;
  final PulsePeriod period;
  final List<WrappedRankedItem> Function(WrappedSummary summary) select;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('wrapped-ranking'),
      appBar: AppBar(title: Text('$title · ${WrappedFormat.period(period)}')),
      body: _SummaryView(
        period: period,
        builder: (context, summary) {
          final items = select(summary);
          if (items.isEmpty) {
            return const SonusStateView(
              icon: Icons.music_off_outlined,
              title: 'Nothing streamed in this period',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final item in items)
                ListTile(
                  key: ValueKey<String>('wrapped-item-${item.rank}'),
                  leading: Text(
                    '${item.rank}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    [
                      if (item.subtitle.isNotEmpty) item.subtitle,
                      '${WrappedFormat.streams(item.streams)} · '
                          '${WrappedFormat.time(item.listened)}',
                      if (item.badge != null) item.badge!,
                    ].join('\n'),
                  ),
                  isThreeLine: item.subtitle.isNotEmpty || item.badge != null,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Genres by streams; streams without a genre are named, never guessed.
class WrappedGenresPage extends StatelessWidget {
  const WrappedGenresPage({super.key, required this.period});

  final PulsePeriod period;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('wrapped-genres'),
      appBar: AppBar(title: Text('Genres · ${WrappedFormat.period(period)}')),
      body: _SummaryView(
        period: period,
        builder: (context, summary) {
          final colors = SonusTheme.of(context).colors;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (summary.genres.isEmpty)
                const Text(
                  'None of this period\'s streams have a genre yet. Genres '
                  'come from the genre of each release in your library.',
                  key: ValueKey<String>('wrapped-genres-empty'),
                ),
              for (final genre in summary.genres)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${genre.genre}: ${WrappedFormat.streams(genre.streams)} '
                          '(${(genre.share * 100).round()}%)',
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: LinearProgressIndicator(
                            value: genre.share,
                            color: colors.progressActive,
                            backgroundColor: colors.progressInactive,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (summary.streamsWithoutGenre > 0)
                Text(
                  '${WrappedFormat.streams(summary.streamsWithoutGenre)} from '
                  'releases without a genre aren\'t counted here.',
                  key: const ValueKey<String>('wrapped-genres-unknown'),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Streams over the period: by day and week for a month, by month for a
/// year. Time before history or after today is never drawn as zero.
class WrappedActivityPage extends StatelessWidget {
  const WrappedActivityPage({super.key, required this.period});

  final PulsePeriod period;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('wrapped-activity'),
      appBar: AppBar(
        title: Text('Listening · ${WrappedFormat.period(period)}'),
      ),
      body: _SummaryView(
        period: period,
        builder: (context, summary) {
          final year = period.kind == PulsePeriodKind.year;
          final points = year
              ? [
                  for (final month in summary.months)
                    WrappedActivityPoint(
                      startLocal: month.period.startLocal,
                      endLocal: month.period.endLocal,
                      streams: month.totals.streams,
                      listened: month.totals.listened,
                      recorded:
                          month.state == WrappedPeriodState.complete ||
                          month.state == WrappedPeriodState.inProgress,
                    ),
                ]
              : summary.days;
          String label(WrappedActivityPoint p) => year
              ? WrappedFormat.shortMonth(p.startLocal.month)
              : '${p.startLocal.day}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(year ? 'Streams by month' : 'Streams by day'),
              const SizedBox(height: 8),
              SonusBarStrip(
                key: const ValueKey<String>('wrapped-activity-bars'),
                bars: [
                  for (final point in points)
                    SonusBar(
                      value: point.streams.toDouble(),
                      spokenLabel: point.recorded
                          ? '${label(point)}: '
                                '${WrappedFormat.streams(point.streams)}'
                          : '${label(point)}: no history',
                      axisLabel: year ? label(point)[0] : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!year) ...[
                const Text('Streams by week'),
                for (final week in summary.weeks)
                  ListTile(
                    title: Text(
                      '${WrappedFormat.day(week.startLocal)} – '
                      '${WrappedFormat.day(week.endLocal.subtract(const Duration(days: 1)))}',
                    ),
                    subtitle: Text(
                      week.recorded
                          ? '${WrappedFormat.streams(week.streams)} · '
                                '${WrappedFormat.time(week.listened)}'
                          : 'No listening history',
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A year's months as a table: each row is that month's own Wrapped.
class WrappedMonthsPage extends StatelessWidget {
  const WrappedMonthsPage({super.key, required this.period});

  final PulsePeriod period;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('wrapped-months'),
      appBar: AppBar(
        title: Text('Month by month · ${WrappedFormat.period(period)}'),
      ),
      body: _SummaryView(
        period: period,
        builder: (context, summary) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final month in summary.months)
              ListTile(
                key: ValueKey<String>(
                  'wrapped-month-row-${month.period.month}',
                ),
                title: Text(WrappedFormat.monthName(month.period.month)),
                subtitle: Text(switch (month.state) {
                  WrappedPeriodState.future => 'Not yet',
                  WrappedPeriodState.beforeHistory => 'No listening history',
                  _ => [
                    '${WrappedFormat.streams(month.totals.streams)} · '
                        '${WrappedFormat.time(month.totals.listened)}',
                    '${month.totals.songs} songs · '
                        '${month.totals.artists} artists',
                    if (month.topSong case final song?)
                      'Top song: ${song.title}',
                    if (month.state == WrappedPeriodState.inProgress)
                      'In progress',
                  ].join('\n'),
                }),
                isThreeLine: month.totals.streams > 0,
                onTap:
                    month.state == WrappedPeriodState.future ||
                        month.state == WrappedPeriodState.beforeHistory
                    ? null
                    : () => _push(
                        context,
                        WrappedPeriodPage(period: month.period),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
