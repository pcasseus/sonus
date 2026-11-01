import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design/sonus_artwork_palette.dart';
import '../../../core/design/sonus_theme.dart';
import '../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../core/design/widgets/sonus_bar_strip.dart';
import '../../../core/design/widgets/sonus_surface_card.dart';
import '../../analytics/presentation/pulse/pulse_format.dart';
import '../../charts/presentation/models/chart_entry_movement.dart';
import '../../charts/presentation/models/chart_week_label.dart';
import '../../charts/presentation/widgets/chart_board_rows.dart';
import '../../charts/presentation/widgets/chart_extended_divider.dart';
import '../../charts/presentation/widgets/chart_movement_indicator.dart';
import '../../library/application/models/library_track.dart';
import '../../player/application/controllers/playback_coordinator.dart';
import '../application/song_stats_models.dart';
import '../application/song_stats_service.dart';
import 'widgets/song_rank_history_chart.dart';

/// Song Stats (Charts 2.0 C4): one page for any song, opened from chart rows
/// and song menus. Chart History first, Personal Listening second. Shows
/// only what Sonus recorded; never invents a rank, label or figure.
class SongStatsPage extends StatefulWidget {
  const SongStatsPage({
    super.key,
    required this.songId,
    this.initialTitle,
    this.playContext,
    this.loader,
    this.now,
  });

  static const routeName = 'song-stats';

  final String songId;

  /// Shown while loading.
  final String? initialTitle;

  /// What Play starts from; the song alone when null.
  final List<LibraryTrack>? playContext;

  /// The data source; the app's [SongStatsLoader] when null.
  final SongStatsLoader? loader;

  /// For the live chart's 24-hour NEW / RE-ENTRY highlight; tests fix it.
  final DateTime Function()? now;

  @override
  State<SongStatsPage> createState() => _SongStatsPageState();
}

class _SongStatsPageState extends State<SongStatsPage> {
  Future<SongStats>? _stats;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void didUpdateWidget(SongStatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        !identical(oldWidget.loader, widget.loader)) {
      _load();
    }
  }

  void _load() {
    final loader = widget.loader ?? _appLoader(context);
    setState(() {
      _stats = loader?.load(widget.songId);
    });
  }

  static SongStatsLoader? _appLoader(BuildContext context) {
    try {
      return context.read<SongStatsLoader?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return Scaffold(
      key: const ValueKey<String>('song-stats-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Song Stats'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<SongStats>(
        future: _stats,
        builder: (context, snapshot) {
          if (_stats == null) {
            return const _Message(
              icon: Icons.insights_rounded,
              title: 'Song Stats are not available',
              message: 'Stats load once your library is open.',
            );
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.error_outline_rounded,
              title: 'Song Stats could not be loaded',
              message: 'Try again.',
              action: FilledButton.icon(
                key: const ValueKey<String>('song-stats-retry'),
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            );
          }
          final stats = snapshot.data;
          if (stats == null) {
            return Center(
              child: Semantics(
                label: widget.initialTitle == null
                    ? 'Loading Song Stats'
                    : 'Loading stats for ${widget.initialTitle}',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          return _SongStatsBody(
            stats: stats,
            playContext: widget.playContext,
            now: widget.now ?? DateTime.now,
          );
        },
      ),
    );
  }
}

class _SongStatsBody extends StatelessWidget {
  const _SongStatsBody({
    required this.stats,
    required this.playContext,
    required this.now,
  });

  final SongStats stats;
  final List<LibraryTrack>? playContext;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Comfortable reading width on tablets and landscape.
        final width = constraints.maxWidth;
        final side = width > 720 ? (width - 720) / 2 : 0.0;
        return ListView(
          key: const ValueKey<String>('song-stats-list'),
          padding: EdgeInsets.fromLTRB(16 + side, 4, 16 + side, 32),
          children: [
            _Hero(identity: stats.identity, playContext: playContext),
            const SizedBox(height: 24),
            _SectionTitle(
              key: const ValueKey<String>('song-stats-chart-title'),
              icon: Icons.leaderboard_rounded,
              title: 'Chart History',
            ),
            const SizedBox(height: 10),
            _ChartHistorySection(history: stats.chart, now: now),
            const SizedBox(height: 28),
            _SectionTitle(
              key: const ValueKey<String>('song-stats-listening-title'),
              icon: Icons.headphones_rounded,
              title: 'Personal Listening',
            ),
            const SizedBox(height: 10),
            _ListeningSection(listening: stats.listening),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Hero

class _Hero extends StatefulWidget {
  const _Hero({required this.identity, required this.playContext});

  final SongStatsIdentity identity;
  final List<LibraryTrack>? playContext;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  SonusArtworkColors? _art;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = widget.identity.artworkPath;
    if (path == _loadedFor) return;
    _loadedFor = path;
    final brightness = Theme.of(context).brightness;
    SonusArtworkPalette.shared.colorsFor(path, brightness: brightness).then((
      colors,
    ) {
      if (mounted && _loadedFor == path) setState(() => _art = colors);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final identity = widget.identity;
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    final gradient = tokens.decoration.allowGradients && !grey;
    final accent = _art?.accent ?? colors.accentPrimary;
    final playback = _playbackOf(context);
    final track = identity.track;
    final canPlay = identity.isPlayable && playback != null && track != null;
    final badge = identity.status.badge;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius + 4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final art = constraints.maxWidth < 360 ? 88.0 : 116.0;
        // Large text on a narrow screen: artwork above the words, so a
        // title never breaks inside a word.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth - 28 - art - 14 < 150 * scale;
        return Container(
          key: const ValueKey<String>('song-stats-hero'),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: gradient ? accent.withValues(alpha: 0.55) : colors.border,
              width: gradient ? 1.5 : 1,
            ),
            color: colors.surface,
            gradient: gradient
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        accent.withValues(alpha: 0.34),
                        colors.surface,
                      ),
                      Color.alphaBlend(
                        colors.accentSecondary.withValues(alpha: 0.12),
                        colors.surface,
                      ),
                    ],
                  )
                : null,
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flex(
                direction: stacked ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SonusArtworkImage(
                    path: identity.artworkPath,
                    size: art,
                    semanticLabel: 'Artwork for ${identity.title}',
                  ),
                  SizedBox(width: 14, height: stacked ? 12 : 0),
                  _HeroText(
                    stacked: stacked,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.title,
                          key: const ValueKey<String>('song-stats-title'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (identity.artistLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            identity.artistLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (identity.albumTitle case final album?
                            when album.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            album,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        if (badge != null) ...[
                          const SizedBox(height: 8),
                          _Pill(
                            key: const ValueKey<String>('song-stats-status'),
                            text: badge,
                            color: theme.colorScheme.error,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (canPlay) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const ValueKey<String>('song-stats-play'),
                    onPressed: () {
                      final context = widget.playContext;
                      final list = context == null || context.isEmpty
                          ? [track]
                          : context;
                      unawaited(playback.playInContext(track, list));
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static PlaybackCoordinator? _playbackOf(BuildContext context) {
    try {
      return context.read<PlaybackCoordinator?>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

// ---------------------------------------------------------------- Chart

class _ChartHistorySection extends StatefulWidget {
  const _ChartHistorySection({required this.history, required this.now});

  final SongChartHistory history;
  final DateTime Function() now;

  @override
  State<_ChartHistorySection> createState() => _ChartHistorySectionState();
}

class _ChartHistorySectionState extends State<_ChartHistorySection> {
  static const _collapsedWeeks = 8;
  bool _allWeeks = false;

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    if (history.isEmpty) {
      return const _EmptyCard(
        key: ValueKey<String>('song-stats-chart-empty'),
        icon: Icons.leaderboard_outlined,
        title: 'No chart stats available',
        message:
            'This song has not held a Hot 100 or Bubbling Under position '
            'in a recorded chart week.',
      );
    }

    final weeks = history.weeks.reversed.toList();
    final shown = _allWeeks || weeks.length <= _collapsedWeeks
        ? weeks
        : weeks.take(_collapsedWeeks).toList();

    final weekly = history.hasFinalized || history.live != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The career standings are what the Charts page opens on; the live
        // card is this week's chart. Both are named, so a song high this
        // week but low in its career reads as two charts, not a conflict.
        if (history.career case final career?) ...[
          _CareerCard(career: career),
          const SizedBox(height: 12),
        ],
        if (history.live case final live?) ...[
          _LiveCard(live: live, now: widget.now),
          const SizedBox(height: 12),
        ],
        if (history.hasFinalized)
          _FinalizedTiles(history: history)
        else
          const _Note(
            key: ValueKey<String>('song-stats-no-finalized'),
            text:
                'Not on a finalized weekly chart yet. A week becomes '
                'permanent when it is finalized with this song on it.',
          ),
        if (weekly) ...[
          const SizedBox(height: 12),
          SonusSurfaceCard(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CardTitle('Position by week'),
                const SizedBox(height: 8),
                SongRankHistoryChart(history: history),
                const SizedBox(height: 6),
                _Note(
                  text: history.live == null
                      ? 'Finalized weeks. Gaps are weeks off the chart.'
                      : 'Solid points are finalized weeks; the hollow point '
                            'is this week, live and provisional.',
                ),
              ],
            ),
          ),
        ],
        if (weeks.isNotEmpty) ...[
          const SizedBox(height: 12),
          SonusSurfaceCard(
            key: const ValueKey<String>('song-stats-week-log'),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CardTitle('Finalized weeks'),
                const SizedBox(height: 4),
                for (final week in shown) _WeekRow(week: week),
                if (shown.length < weeks.length)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey<String>('song-stats-all-weeks'),
                      onPressed: () => setState(() => _allWeeks = true),
                      child: Text('Show all ${weeks.length} weeks'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The song's place in the career standings (all-time, by lifetime
/// streams), as its row on the Charts page shows it.
class _CareerCard extends StatelessWidget {
  const _CareerCard({required this.career});

  final SongCareerStanding career;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final zone = career.isHot100
        ? ChartZoneNames.hot100
        : ChartZoneNames.bubblingUnder;

    return SonusSurfaceCard(
      key: const ValueKey<String>('song-stats-career'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Career standings',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${career.rank}',
                key: const ValueKey<String>('song-stats-career-rank'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                zone,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const _Note(
            text:
                'All time, by lifetime streams: the chart the Charts page '
                'opens on.',
          ),
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.now});

  final SongLiveChart live;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final movement = ChartEntryMovement.of(
      live.entry,
      live: true,
      now: now(),
      weekStartUtc: live.weekStartUtc,
      weekEndUtc: live.weekEndUtc,
    );
    final zone = live.isHot100
        ? ChartZoneNames.hot100
        : ChartZoneNames.bubblingUnder;
    final best = live.bestSoFarRank;

    return SonusSurfaceCard(
      key: const ValueKey<String>('song-stats-live'),
      raised: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'This week',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              _Pill(
                key: const ValueKey<String>('song-stats-live-pill'),
                text: 'LIVE · PROVISIONAL',
                color: colors.accentPrimary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${live.rank}',
                key: const ValueKey<String>('song-stats-live-rank'),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // Scales down rather than overflow at large text (as in
              // the chart rows).
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ChartMovementIndicator(
                  entry: live.entry,
                  movement: movement,
                ),
              ),
            ],
          ),
          Text(
            zone,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (best != null && best != live.rank) ...[
            const SizedBox(height: 4),
            Text(
              'Best so far this week: #$best',
              key: const ValueKey<String>('song-stats-live-best'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const _Note(
            text:
                'Live positions can change until this chart week is '
                'finalized. They never count as a peak.',
          ),
        ],
      ),
    );
  }
}

class _FinalizedTiles extends StatelessWidget {
  const _FinalizedTiles({required this.history});

  final SongChartHistory history;

  static String _zone(int rank) => rank <= 100 ? 'Hot 100' : 'Bubbling Under';

  static String _weeks(int n) => n == 1 ? '1 week' : '$n weeks';

  @override
  Widget build(BuildContext context) {
    final peak = history.peakRank!;
    final peakWeek = history.firstPeakWeek!;
    final last = history.lastFinalized!;
    final debut = history.debut!;
    final hot100Debut = history.hot100Debut;

    return _TileGrid(
      tiles: [
        _Tile(
          key: const ValueKey<String>('song-stats-peak'),
          label: 'Peak',
          value: '#$peak',
          caption:
              '${_zone(peak)} · ${_weeks(history.weeksAtPeak)} at peak\n'
              'First reached week of ${chartShortDate(peakWeek.weekStartUtc)}',
          featured: true,
        ),
        _Tile(
          key: const ValueKey<String>('song-stats-last'),
          label: 'Last finalized',
          value: '#${last.rank}',
          caption:
              '${_zone(last.rank)} · week of '
              '${chartShortDate(last.weekStartUtc)}',
        ),
        _Tile(
          key: const ValueKey<String>('song-stats-hot100-weeks'),
          label: 'Weeks on Hot 100',
          value: '${history.hot100Weeks}',
        ),
        _Tile(
          key: const ValueKey<String>('song-stats-bu-weeks'),
          label: 'Weeks Bubbling Under',
          value: '${history.bubblingUnderWeeks}',
        ),
        _Tile(
          key: const ValueKey<String>('song-stats-debut'),
          label: 'Debut',
          value: '#${debut.rank}',
          caption:
              '${_zone(debut.rank)} · week of '
              '${chartShortDate(debut.weekStartUtc)}',
        ),
        if (hot100Debut != null && !identical(hot100Debut, debut))
          _Tile(
            key: const ValueKey<String>('song-stats-hot100-debut'),
            label: 'Hot 100 debut',
            value: '#${hot100Debut.rank}',
            caption: 'Week of ${chartShortDate(hot100Debut.weekStartUtc)}',
          ),
        _Tile(
          key: const ValueKey<String>('song-stats-reentries'),
          label: 'Re-entries',
          value: '${history.reentries}',
        ),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.week});

  final SongChartWeek week;

  String get _event => switch (week.event) {
    SongChartWeekEvent.debut => 'Debut',
    SongChartWeekEvent.reentry =>
      week.weeksOff == 1
          ? 'Re-entry after 1 week off'
          : 'Re-entry after ${week.weeksOff} weeks off',
    SongChartWeekEvent.up => 'Up ${week.positions}',
    SongChartWeekEvent.down => 'Down ${-week.positions!}',
    SongChartWeekEvent.same => 'No change',
    SongChartWeekEvent.promoted =>
      'Into the Hot 100 from Bubbling Under (#${week.previousRank})',
    SongChartWeekEvent.demoted =>
      'To Bubbling Under from the Hot 100 (#${week.previousRank})',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    final eventColor = switch (week.event) {
      SongChartWeekEvent.up || SongChartWeekEvent.promoted => colors.chartUp,
      SongChartWeekEvent.down || SongChartWeekEvent.demoted => colors.chartDown,
      SongChartWeekEvent.debut => colors.chartNew,
      SongChartWeekEvent.reentry => colors.chartReentry,
      SongChartWeekEvent.same => colors.textSecondary,
    };
    final zone = week.isHot100 ? 'Hot 100' : 'Bubbling Under';
    final label = chartWeekLabel(week.weekStartUtc, week.weekEndUtc);
    final badges = [
      if (week.newPeak) 'NEW PEAK',
      if (week.hot100Debut && week.event != SongChartWeekEvent.debut)
        'HOT 100 DEBUT',
    ];

    return Semantics(
      container: true,
      label: [
        label,
        'number ${week.rank}',
        zone,
        _event,
        ...badges.map((b) => b.toLowerCase()),
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        key: ValueKey<String>(
          'song-stats-week-${week.weekStartUtc.toIso8601String()}',
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(46).clamp(46, 76),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '#${week.rank}',
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: week.isHot100
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _event,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: grey ? colors.textPrimary : eventColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$label · $zone',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final b in badges)
                          _Pill(
                            text: b,
                            color: grey
                                ? colors.textPrimary
                                : colors.accentTertiary,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Listening

enum _TrendMeasure { minutes, streams }

class _ListeningSection extends StatefulWidget {
  const _ListeningSection({required this.listening});

  final SongListeningStats listening;

  @override
  State<_ListeningSection> createState() => _ListeningSectionState();
}

class _ListeningSectionState extends State<_ListeningSection> {
  _TrendMeasure _measure = _TrendMeasure.minutes;

  @override
  Widget build(BuildContext context) {
    final listening = widget.listening;
    if (!listening.hasAny) {
      return const _EmptyCard(
        key: ValueKey<String>('song-stats-listening-empty'),
        icon: Icons.headphones_outlined,
        title: 'No listening recorded',
        message:
            'Streams and listening time appear after this song is played '
            'in Sonus.',
      );
    }

    final hasTime = listening.listened > Duration.zero;
    final first = listening.firstPlayedAt;
    final last = listening.lastPlayedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TileGrid(
          tiles: [
            _Tile(
              key: const ValueKey<String>('song-stats-streams'),
              label: 'Streams',
              value: PulseFormat.grouped(listening.streams),
              caption: 'Qualified plays, all time',
              featured: true,
            ),
            _Tile(
              key: const ValueKey<String>('song-stats-minutes'),
              label: 'Listening time',
              value: hasTime ? PulseFormat.duration(listening.listened) : '—',
              caption: hasTime
                  ? 'Audible time, all time'
                  : 'No audible time recorded',
            ),
            _Tile(
              key: const ValueKey<String>('song-stats-plays'),
              label: 'All plays',
              value: PulseFormat.grouped(listening.allPlays),
              caption: listening.allPlays == 0
                  ? 'No plays with audible time recorded'
                  : 'Plays with audible time',
            ),
            _Tile(
              key: const ValueKey<String>('song-stats-first-played'),
              label: 'First played',
              value: first == null ? '—' : chartShortDate(first),
              caption: first == null ? 'Not recorded' : null,
            ),
            _Tile(
              key: const ValueKey<String>('song-stats-last-played'),
              label: 'Last played',
              value: last == null ? '—' : chartShortDate(last),
              caption: last == null ? 'Not recorded' : null,
            ),
          ],
        ),
        if (listening.weeks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TrendCard(
            weeks: listening.weeks,
            measure: _measure,
            onMeasure: (m) => setState(() => _measure = m),
          ),
        ],
        if (listening.historyStartedAt case final since?) ...[
          const SizedBox(height: 8),
          _Note(
            key: const ValueKey<String>('song-stats-history-since'),
            text:
                'Recorded listening in Sonus begins ${chartShortDate(since)}.',
          ),
        ],
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.weeks,
    required this.measure,
    required this.onMeasure,
  });

  final List<SongListeningWeek> weeks;
  final _TrendMeasure measure;
  final ValueChanged<_TrendMeasure> onMeasure;

  @override
  Widget build(BuildContext context) {
    final minutes = measure == _TrendMeasure.minutes;
    double valueOf(SongListeningWeek w) =>
        minutes ? w.listened.inSeconds / 60 : w.streams.toDouble();
    var peak = -1;
    for (final (i, w) in weeks.indexed) {
      if (valueOf(w) > 0 && (peak < 0 || valueOf(w) > valueOf(weeks[peak]))) {
        peak = i;
      }
    }
    String amount(SongListeningWeek w) => minutes
        ? (w.listened > Duration.zero
              ? PulseFormat.duration(w.listened)
              : 'no listening')
        : '${w.streams} ${w.streams == 1 ? 'stream' : 'streams'}';
    final firstWeek = weeks.first;
    final lastWeek = weeks.last;

    return SonusSurfaceCard(
      key: const ValueKey<String>('song-stats-trend'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const _CardTitle('Weekly listening'),
              SegmentedButton<_TrendMeasure>(
                key: const ValueKey<String>('song-stats-trend-measure'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _TrendMeasure.minutes,
                    label: Text('Time'),
                  ),
                  ButtonSegment(
                    value: _TrendMeasure.streams,
                    label: Text('Streams'),
                  ),
                ],
                selected: {measure},
                onSelectionChanged: (s) => onMeasure(s.single),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SonusBarStrip(
            height: 96,
            highlightIndex: peak < 0 ? null : peak,
            highlightLabel: 'Busiest week',
            bars: [
              for (final (i, w) in weeks.indexed)
                SonusBar(
                  value: valueOf(w),
                  spokenLabel:
                      'Week of ${chartShortDate(w.weekStartLocal)}'
                      '${w.inProgress ? ', so far' : ''}: ${amount(w)}',
                  axisLabel: i == 0
                      ? PulseFormat.shortDay(w.weekStartLocal)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          _Note(
            text:
                'Chart weeks from ${chartShortDate(firstWeek.weekStartLocal)}. '
                'This week so far: ${amount(lastWeek)}.'
                '${peak >= 0 ? ' Busiest: week of '
                          '${chartShortDate(weeks[peak].weekStartLocal)}, '
                          '${amount(weeks[peak])}.' : ''}',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Pieces

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final minTile = 148 * scale.clamp(1.0, 1.6);
        final columns = (constraints.maxWidth / minTile).floor().clamp(1, 3);
        const gap = 10.0;
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

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.featured = false,
  });

  final String label;
  final String value;
  final String? caption;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    final tint = featured && tokens.decoration.allowGradients && !grey;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    return Semantics(
      container: true,
      label: [label, value, ?caption].join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: colors.surface,
          border: Border.all(
            color: featured && !tint ? colors.focus : colors.divider,
          ),
          gradient: tint
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      colors.accentPrimary.withValues(alpha: 0.22),
                      colors.surface,
                    ),
                    Color.alphaBlend(
                      colors.accentSecondary.withValues(alpha: 0.14),
                      colors.surface,
                    ),
                  ],
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (caption case final text?) ...[
              const SizedBox(height: 2),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final grey = chartThemeIsGreyscale(colors.accentPrimary);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: grey ? colors.textPrimary : colors.accentPrimary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: SonusTheme.of(context).colors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: SonusTheme.of(context).colors.textSecondary,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tokens.colors.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    return SonusSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _Message extends StatelessWidget {
  const _Message({
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// The hero's words: beside the artwork (filling the row) or below it.
class _HeroText extends StatelessWidget {
  const _HeroText({required this.stacked, required this.child});

  final bool stacked;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      stacked ? child : Expanded(child: child);
}
