import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../library/application/models/library_track.dart';
import '../../application/models/pulse/pulse_delta.dart';
import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import '../../application/services/pulse/pulse_entity_directory.dart';
import 'pulse_colors.dart';
import 'pulse_format.dart';
import 'pulse_hero.dart';

/// What a ranking card can ask the page to do. All use existing app
/// services (the page wires them to PlaybackCoordinator and the artist and
/// album profiles).
class PulseRankingActions {
  const PulseRankingActions({
    this.playTracks,
    this.openArtist,
    this.openRelease,
  });

  /// Plays [tracks] from [start] (PlaybackCoordinator.playInContext).
  final void Function(LibraryTrack start, List<LibraryTrack> tracks)?
  playTracks;
  final void Function(String artistId, String name)? openArtist;
  final void Function(String albumId, String title)? openRelease;
}

/// One ranking card (spec §6): Top artists, Top tracks, or Top albums & EPs
/// (Singles excluded by [PulsePeriodData.ranking]).
class PulseRankingCard extends StatefulWidget {
  const PulseRankingCard({
    super.key,
    required this.kind,
    required this.data,
    required this.directory,
    required this.palette,
    required this.accent,
    this.comparisonData,
    this.comparisonTitle,
    this.focus,
    this.onFocusChanged,
    this.lifetimeStreams,
    this.actions = const PulseRankingActions(),
    this.artworkPalette,
  });

  final PulseEntityKind kind;
  final PulsePeriodData data;
  final PulseEntityDirectory directory;
  final PulsePalette palette;

  /// The temporary artwork accent shared with the hero.
  final PulseAccentController accent;

  /// The comparison period's data, for rank movement; null when there is
  /// no eligible comparison.
  final PulsePeriodData? comparisonData;
  final String? comparisonTitle;

  /// The item open anywhere on the page; this card shows its detail when it
  /// is one of its own.
  final PulseItemFocus? focus;
  final ValueChanged<PulseItemFocus?>? onFocusChanged;
  final Future<int?> Function(PulseEntityKind kind, String id)? lifetimeStreams;
  final PulseRankingActions actions;
  final SonusArtworkPalette? artworkPalette;

  static const sizes = [5, 10, 25];

  String get title => switch (kind) {
    PulseEntityKind.artist => 'Top artists',
    PulseEntityKind.track => 'Top tracks',
    PulseEntityKind.release => 'Top albums & EPs',
  };

  @override
  State<PulseRankingCard> createState() => _PulseRankingCardState();
}

class _PulseRankingCardState extends State<PulseRankingCard> {
  // Remembered for the session while the page lives (spec §6).
  PulseMeasure _metric = PulseMeasure.streams;
  int _size = 5;

  PulseItemFocus? get _ownFocus {
    final focus = widget.focus;
    return focus != null && focus.kind == widget.kind ? focus : null;
  }

  void _toggle(PulseEntityInfo info) {
    final open = _ownFocus?.id == info.id;
    if (open) {
      _close();
      return;
    }
    widget.accent.reset();
    widget.onFocusChanged?.call(
      PulseItemFocus(kind: widget.kind, id: info.id, name: info.title),
    );
    final palette = widget.artworkPalette ?? SonusArtworkPalette.shared;
    final brightness = Theme.of(context).brightness;
    unawaited(
      palette.colorsFor(info.artworkPath, brightness: brightness).then((c) {
        // Only if this item is still the open one.
        if (!mounted || widget.focus?.id != info.id) return;
        widget.accent.apply(c);
      }),
    );
  }

  void _close() {
    widget.accent.reset();
    widget.onFocusChanged?.call(null);
  }

  @override
  void didUpdateWidget(PulseRankingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A period change closes the detail and returns the theme colours.
    if (oldWidget.data.period != widget.data.period && _ownFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final ranking = widget.data.ranking(widget.kind, _metric);
    final shown = ranking.take(_size).toList();
    final previous = widget.comparisonData == null
        ? null
        : {
            for (final e in widget.comparisonData!.ranking(
              widget.kind,
              _metric,
            ))
              e.id: e.rank,
          };
    final ramp = widget.palette.rampFor(_metric);
    final top = shown.isEmpty ? 0 : shown.first.metrics.valueOf(_metric);
    final open = _ownFocus;

    return ListenableBuilder(
      listenable: widget.accent,
      builder: (context, _) {
        final accentPalette = open == null
            ? widget.palette
            : PulsePalette.resolve(
                colors: colors,
                decoration: theme.decoration,
                highContrast: widget.palette.highContrast,
                artwork: widget.accent.artwork,
              );
        final tint = open != null && accentPalette.itemAccent != null
            ? SonusArtworkAtmosphere.resolve(
                colors: colors,
                decoration: theme.decoration,
                artwork: widget.accent.artwork,
              )
            : null;
        return AnimatedContainer(
          duration: theme.motion.medium,
          decoration: BoxDecoration(
            color: tint?.surface ?? colors.surface,
            borderRadius: BorderRadius.circular(theme.metrics.cardRadius),
            border: widget.palette.highContrast
                ? Border.all(color: colors.border)
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, ranking.length),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nothing to rank by ${_metricName(_metric).toLowerCase()} '
                    'in ${PulseFormat.periodTitle(widget.data.period)}.',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              _resizing(
                context,
                Column(
                  key: ValueKey('pulse-ranking-${widget.kind.name}-$_size'),
                  children: [
                    for (final entry in shown) ...[
                      _PulseRankingRow(
                        entry: entry,
                        info: widget.directory.infoFor(widget.kind, entry.id),
                        measure: _metric,
                        ramp: ramp,
                        palette: widget.palette,
                        share: top <= 0
                            ? 0
                            : (entry.metrics.valueOf(_metric) / top).toDouble(),
                        previousRank: previous == null
                            ? null
                            : (previous[entry.id] ?? 0),
                        open: open?.id == entry.id,
                        onTap: () => _toggle(
                          widget.directory.infoFor(widget.kind, entry.id),
                        ),
                      ),
                      if (open?.id == entry.id)
                        PulseItemDetail(
                          key: ValueKey('pulse-detail-${entry.id}'),
                          entry: entry,
                          info: widget.directory.infoFor(widget.kind, entry.id),
                          data: widget.data,
                          directory: widget.directory,
                          measure: _metric,
                          palette: accentPalette,
                          accentApplied: widget.accent.isApplied,
                          comparisonData: widget.comparisonData,
                          comparisonTitle: widget.comparisonTitle,
                          previousRank: previous?[entry.id],
                          lifetimeStreams: widget.lifetimeStreams,
                          actions: widget.actions,
                          onResetColours: widget.accent.reset,
                          onClose: _close,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resizing(BuildContext context, Widget child) {
    final motion = SonusTheme.of(context).motion;
    // AnimatedSize asserts with a zero duration (reduced motion).
    if (motion.reduced) return child;
    return AnimatedSize(
      duration: motion.medium,
      curve: motion.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  Widget _header(BuildContext context, int available) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Narrow or large text: the metric menu goes under the title so
        // the title keeps its width.
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Semantics(
              header: true,
              child: Text(widget.title, style: theme.text.sectionHeading),
            );
            final menu = PopupMenuButton<PulseMeasure>(
              key: ValueKey('pulse-metric-${widget.kind.name}'),
              tooltip: 'Rank by',
              initialValue: _metric,
              onSelected: (m) => setState(() => _metric = m),
              itemBuilder: (_) => [
                for (final m in const [
                  PulseMeasure.streams,
                  PulseMeasure.minutes,
                  PulseMeasure.allPlays,
                ])
                  PopupMenuItem(value: m, child: Text(_metricName(m))),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _metricName(_metric),
                      style: TextStyle(
                        color: widget.palette.rampFor(_metric).at(0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: colors.textSecondary),
                  ],
                ),
              ),
            );
            final stacked =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) >= 1.3;
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, menu],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      menu,
                    ],
                  );
          },
        ),
        if (available > PulseRankingCard.sizes.first)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              children: [
                for (final size in PulseRankingCard.sizes)
                  if (size == PulseRankingCard.sizes.first ||
                      available > size ~/ 2)
                    ChoiceChip(
                      key: ValueKey('pulse-top-${widget.kind.name}-$size'),
                      label: Text('Top $size'),
                      selected: _size == size,
                      onSelected: (_) => setState(() => _size = size),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

String _metricName(PulseMeasure m) => switch (m) {
  PulseMeasure.streams => 'Streams',
  PulseMeasure.minutes => 'Minutes',
  PulseMeasure.allPlays => 'All plays',
};

String _value(PulseMetrics m, PulseMeasure measure) => switch (measure) {
  PulseMeasure.minutes => '${PulseFormat.grouped(m.listened.inMinutes)} min',
  PulseMeasure.streams => PulseFormat.grouped(m.streams),
  PulseMeasure.allPlays => PulseFormat.grouped(m.allPlays),
};

String _spokenValue(PulseMetrics m, PulseMeasure measure) => switch (measure) {
  PulseMeasure.minutes =>
    '${PulseFormat.grouped(m.listened.inMinutes)} minutes',
  PulseMeasure.streams =>
    '${PulseFormat.grouped(m.streams)} ${m.streams == 1 ? 'stream' : 'streams'}',
  PulseMeasure.allPlays =>
    '${PulseFormat.grouped(m.allPlays)} ${m.allPlays == 1 ? 'play' : 'plays'}',
};

class _PulseRankingRow extends StatelessWidget {
  const _PulseRankingRow({
    required this.entry,
    required this.info,
    required this.measure,
    required this.ramp,
    required this.palette,
    required this.share,
    required this.previousRank,
    required this.open,
    required this.onTap,
  });

  final PulseRankedEntity entry;
  final PulseEntityInfo info;
  final PulseMeasure measure;
  final PulseRamp ramp;
  final PulsePalette palette;

  /// The row's value as a share of #1.
  final double share;

  /// Null without a comparison; 0 when the item is new in this period.
  final int? previousRank;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final barColor = ramp.at(0.25 + 0.75 * share);
    final movement = _movement();
    final badge = info.badge;
    final shape = info.kind == PulseEntityKind.artist ? entry.rank % 3 : 2;

    return Semantics(
      button: true,
      expanded: open,
      label: [
        'Rank ${entry.rank}',
        info.title,
        if (info.subtitle.isNotEmpty) info.subtitle,
        _spokenValue(entry.metrics, measure),
        ?movement?.$3,
        if (badge != null) badge.toLowerCase(),
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('pulse-row-${info.kind.name}-${entry.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.metrics.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Stack(
            children: [
              // The value bar: length is the share of #1, colour climbs the
              // metric's ramp. A thin rule in high contrast.
              Positioned.fill(
                child: Align(
                  alignment: palette.highContrast
                      ? Alignment.bottomLeft
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: share.clamp(0.0, 1.0),
                    heightFactor: palette.highContrast ? null : 1,
                    child: palette.highContrast
                        ? Container(height: 2, color: ramp.tip)
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                theme.metrics.controlRadius,
                              ),
                              gradient: ramp.fill == PulseFill.gradient
                                  ? LinearGradient(
                                      colors: [
                                        ramp.base.withValues(alpha: 0.10),
                                        barColor.withValues(alpha: 0.24),
                                      ],
                                    )
                                  : null,
                              color: ramp.fill == PulseFill.gradient
                                  ? null
                                  : barColor.withValues(alpha: 0.2),
                            ),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${entry.rank}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Artwork(
                      path: info.artworkPath,
                      kind: info.kind,
                      shape: shape,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              if (badge != null) ...[
                                _Badge(badge),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  info.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _value(entry.metrics, measure),
                          style: TextStyle(
                            color: ramp.at(0.85),
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (movement != null)
                          Text(
                            movement.$1,
                            style: TextStyle(
                              color: movement.$2,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
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

  /// (shown, colour, spoken) or null without a comparison.
  (String, Color, String)? _movement() {
    final before = previousRank;
    if (before == null) return null;
    if (before == 0) {
      return ('NEW', palette.allPlays.tip, 'new this period');
    }
    final change = before - entry.rank;
    if (change > 0) {
      return ('▲ $change', palette.chartUp, 'up $change from $before');
    }
    if (change < 0) {
      return (
        '▼ ${-change}',
        palette.chartDown,
        'down ${-change} from $before',
      );
    }
    return ('=', palette.textSecondary, 'same rank');
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.path, required this.kind, required this.shape});

  final String? path;
  final PulseEntityKind kind;

  /// Artists rotate circle (0), rounded square (1), square (2) by rank;
  /// tracks and releases are square.
  final int shape;

  @override
  Widget build(BuildContext context) {
    final radius = SonusTheme.of(context).metrics.artworkRadius;
    final image = SonusArtworkImage(
      path: path,
      size: 44,
      circular: kind == PulseEntityKind.artist && shape == 0,
      placeholderIcon: switch (kind) {
        PulseEntityKind.artist => Icons.person_rounded,
        PulseEntityKind.track => Icons.music_note_rounded,
        PulseEntityKind.release => Icons.album_rounded,
      },
    );
    if (kind == PulseEntityKind.artist && shape == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(math.max(radius, 10)),
        child: image,
      );
    }
    return image;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// The inline detail under an opened row (spec §6): the item in this
/// period, its lifetime streams, its trend, the comparison, related items
/// and actions. Everything is from recorded history.
class PulseItemDetail extends StatefulWidget {
  const PulseItemDetail({
    super.key,
    required this.entry,
    required this.info,
    required this.data,
    required this.directory,
    required this.measure,
    required this.palette,
    required this.accentApplied,
    required this.actions,
    required this.onResetColours,
    required this.onClose,
    this.comparisonData,
    this.comparisonTitle,
    this.previousRank,
    this.lifetimeStreams,
  });

  final PulseRankedEntity entry;
  final PulseEntityInfo info;
  final PulsePeriodData data;
  final PulseEntityDirectory directory;
  final PulseMeasure measure;

  /// With the item's artwork accent when one applies.
  final PulsePalette palette;
  final bool accentApplied;
  final PulsePeriodData? comparisonData;
  final String? comparisonTitle;
  final int? previousRank;
  final Future<int?> Function(PulseEntityKind kind, String id)? lifetimeStreams;
  final PulseRankingActions actions;
  final VoidCallback onResetColours;
  final VoidCallback onClose;

  /// The trend: per day for a month, per calendar month for a year, in
  /// [measure]; the same rows as the totals, so it adds up to them.
  static List<(String, num)> trend(
    PulsePeriodData data,
    PulseEntityKind kind,
    String id,
    PulseMeasure measure,
  ) {
    final series = data.daySeriesFor(kind, id);
    if (data.period.kind == PulsePeriodKind.month) {
      return [
        for (var i = 0; i < series.length; i++)
          ('${data.days[i].localDate.day}', series[i].valueOf(measure)),
      ];
    }
    final months = List<num>.filled(12, 0);
    for (var i = 0; i < series.length; i++) {
      months[data.days[i].localDate.month - 1] += series[i].valueOf(measure);
    }
    return [
      for (var m = 0; m < 12; m++) (PulseFormat.shortMonth(m + 1), months[m]),
    ];
  }

  @override
  State<PulseItemDetail> createState() => _PulseItemDetailState();
}

class _PulseItemDetailState extends State<PulseItemDetail> {
  Future<int?>? _lifetime;

  @override
  void initState() {
    super.initState();
    _lifetime = widget.lifetimeStreams?.call(widget.info.kind, widget.info.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final info = widget.info;
    final data = widget.data;
    final m = widget.entry.metrics;
    final palette = widget.palette;
    final accent = palette.itemAccent;
    final trend = PulseItemDetail.trend(
      data,
      info.kind,
      info.id,
      widget.measure,
    );
    final related = _related();
    final playable = _playable();

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.raisedSurface,
        borderRadius: BorderRadius.circular(theme.metrics.cardRadius),
        border: Border.all(
          color: accent ?? colors.border,
          width: palette.itemOutlineOnly ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'In ${PulseFormat.periodTitle(data.period)}',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _stat(
                'Minutes',
                PulseFormat.grouped(m.listened.inMinutes),
                palette.minutes,
              ),
              _stat('Streams', PulseFormat.grouped(m.streams), palette.streams),
              _stat(
                'All plays',
                PulseFormat.grouped(m.allPlays),
                palette.allPlays,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<int?>(
            future: _lifetime,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (value == null) return const SizedBox.shrink();
              return Text(
                '${PulseFormat.grouped(value)} lifetime '
                '${value == 1 ? 'stream' : 'streams'}',
                key: const ValueKey('pulse-detail-lifetime'),
                style: TextStyle(color: colors.textPrimary),
              );
            },
          ),
          _comparisonLine(colors.textSecondary),
          const SizedBox(height: 10),
          Semantics(
            label:
                'Trend by ${data.period.kind == PulsePeriodKind.month ? 'day' : 'month'}: '
                '${trend.where((t) => t.$2 > 0).map((t) => '${t.$1} ${t.$2 is double ? (t.$2 as double).round() : t.$2}').join(', ')}',
            excludeSemantics: true,
            child: SizedBox(
              height: 56,
              child: CustomPaint(
                size: Size.infinite,
                painter: _TrendPainter(
                  values: [for (final t in trend) t.$2.toDouble()],
                  color: accent ?? palette.rampFor(widget.measure).at(0.8),
                  base: colors.divider,
                ),
              ),
            ),
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final (heading, rows) in related) ...[
              Text(
                heading,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        r.$2,
                        style: TextStyle(
                          color: palette.rampFor(widget.measure).at(0.85),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (widget.actions.playTracks != null)
                FilledButton.tonalIcon(
                  key: const ValueKey('pulse-detail-play'),
                  onPressed: playable.isEmpty
                      ? null
                      : () => widget.actions.playTracks!(
                          playable.first,
                          playable,
                        ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              if (widget.actions.openArtist != null && info.artistId != null)
                OutlinedButton(
                  key: const ValueKey('pulse-detail-open-artist'),
                  onPressed: () => widget.actions.openArtist!(
                    info.artistId!,
                    info.kind == PulseEntityKind.artist
                        ? info.title
                        : info.subtitle,
                  ),
                  child: const Text('Open artist'),
                ),
              if (widget.actions.openRelease != null && info.albumId != null)
                OutlinedButton(
                  key: const ValueKey('pulse-detail-open-release'),
                  onPressed: () => widget.actions.openRelease!(
                    info.albumId!,
                    info.kind == PulseEntityKind.release
                        ? info.title
                        : widget.directory
                              .infoFor(PulseEntityKind.release, info.albumId!)
                              .title,
                  ),
                  child: const Text('Open album'),
                ),
              if (widget.accentApplied)
                TextButton(
                  key: const ValueKey('pulse-detail-reset-colours'),
                  onPressed: widget.onResetColours,
                  child: const Text('Reset colours'),
                ),
              TextButton(
                key: const ValueKey('pulse-detail-close'),
                onPressed: widget.onClose,
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, PulseRamp ramp) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          color: ramp.at(0.85),
          fontWeight: FontWeight.w700,
          fontSize: 18,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );

  Widget _comparisonLine(Color muted) {
    final before = widget.comparisonData;
    final title = widget.comparisonTitle;
    if (before == null || title == null) return const SizedBox.shrink();
    final was = before.totalsFor(widget.info.kind, widget.info.id);
    final now = widget.entry.metrics;
    final delta = PulseDelta.compare(
      _whole(now, widget.measure),
      _whole(was, widget.measure),
    );
    final rank = widget.previousRank;
    final rankText = rank == null || rank == 0
        ? 'not ranked then'
        : 'was #$rank';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'vs $title: ${_value(was, widget.measure)} · '
        '${delta.label} · $rankText',
        key: const ValueKey('pulse-detail-comparison'),
        style: TextStyle(color: muted),
      ),
    );
  }

  static num _whole(PulseMetrics m, PulseMeasure measure) =>
      measure == PulseMeasure.minutes
      ? m.listened.inMinutes
      : m.valueOf(measure);

  /// Artist: top tracks and release contributions. Release: its tracks.
  List<(String, List<(String, String)>)> _related() {
    final data = widget.data;
    final info = widget.info;
    final measure = widget.measure;
    String name(PulseEntityKind k, String id) =>
        widget.directory.infoFor(k, id).title;
    switch (info.kind) {
      case PulseEntityKind.artist:
        final tracks = data.tracksOfArtist(info.id, measure, limit: 3);
        final releases = data
            .releaseContributionsOf(info.id, measure)
            .take(3)
            .toList();
        return [
          if (tracks.isNotEmpty)
            (
              'Top tracks',
              [
                for (final t in tracks)
                  (
                    name(PulseEntityKind.track, t.id),
                    _value(t.metrics, measure),
                  ),
              ],
            ),
          if (releases.isNotEmpty)
            (
              'Releases',
              [
                for (final r in releases)
                  (
                    name(PulseEntityKind.release, r.id),
                    _value(r.metrics, measure),
                  ),
              ],
            ),
        ];
      case PulseEntityKind.release:
        final tracks = data.tracksOfRelease(info.id, measure, limit: 5);
        return [
          if (tracks.isNotEmpty)
            (
              'Tracks',
              [
                for (final t in tracks)
                  (
                    name(PulseEntityKind.track, t.id),
                    _value(t.metrics, measure),
                  ),
              ],
            ),
        ];
      case PulseEntityKind.track:
        return const [];
    }
  }

  /// What Play plays: the track itself, or the artist's or release's
  /// playable tracks from this period's ranking, in order.
  List<LibraryTrack> _playable() {
    final info = widget.info;
    final data = widget.data;
    return switch (info.kind) {
      PulseEntityKind.track => widget.directory.playableTracks([info.id]),
      PulseEntityKind.artist => widget.directory.playableTracks(
        data.tracksOfArtist(info.id, PulseMeasure.streams).map((t) => t.id),
      ),
      PulseEntityKind.release => widget.directory.playableTracks(
        data.tracksOfRelease(info.id, PulseMeasure.streams).map((t) => t.id),
      ),
    };
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.color,
    required this.base,
  });

  final List<double> values;
  final Color color;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final top = values.reduce(math.max);
    final step = size.width / values.length;
    final barWidth = math.max(1.0, step * 0.6);
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = base,
    );
    if (top <= 0) return;
    final paint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / top * (size.height - 2);
      if (h <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * step + (step - barWidth) / 2,
            size.height - h,
            barWidth,
            h,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.color != color || old.base != base;
}
