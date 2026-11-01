import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../settings/application/controllers/appearance_controller.dart';
import '../../application/models/pulse/pulse_delta.dart';
import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import '../../application/models/year_in_sonus/year_in_sonus_recap.dart';
import '../../application/services/year_in_sonus/year_in_sonus_service.dart';
import '../controllers/pulse_insights_controller.dart';
import '../pulse/pulse_colors.dart';
import '../pulse/pulse_format.dart';
import '../pulse/pulse_hero.dart';
import '../pulse/pulse_overview.dart';
import '../pulse/pulse_rankings.dart';
import '../pulse/pulse_year_cards.dart';

/// The Insights destination: Sonus Pulse 2.0. Read-only over listening
/// history; Play and the profile links use the existing playback
/// coordinator and profile pages.
class PulseInsightsPage extends StatefulWidget {
  const PulseInsightsPage({super.key, this.nowLocal});

  final DateTime Function()? nowLocal;

  @override
  State<PulseInsightsPage> createState() => _PulseInsightsPageState();
}

class _PulseInsightsPageState extends State<PulseInsightsPage> {
  final PulseAccentController _accent = PulseAccentController();
  PulseItemFocus? _focus;
  PulsePeriod? _shownPeriod;
  YearInSonusRecap? _recap;
  int? _recapYear;

  @override
  void dispose() {
    // Leaving Insights returns the theme colours (nothing is persisted).
    _accent.dispose();
    super.dispose();
  }

  void _setFocus(PulseItemFocus? focus) {
    setState(() => _focus = focus);
    if (focus == null) _accent.reset();
  }

  /// A period or view change closes any detail and its accent.
  void _trackPeriod(PulsePeriod? period) {
    if (period == _shownPeriod) return;
    _shownPeriod = period;
    if (_focus != null || _accent.isApplied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _accent.reset();
        setState(() => _focus = null);
      });
    }
  }

  void _loadRecap(PulsePeriod period) {
    if (period.kind != PulsePeriodKind.year || _recapYear == period.year) {
      return;
    }
    _recapYear = period.year;
    final loader = context.read<YearInSonusLoader?>();
    if (loader == null) return;
    unawaited(
      loader
          .load(year: period.year)
          .then((recap) {
            if (mounted && _recapYear == recap.year) {
              setState(() => _recap = recap);
            }
          })
          .catchError((Object _) {
            // Milestones then show only what Pulse itself knows.
          }),
    );
  }

  Future<void> _openMonth(
    PulseInsightsController controller,
    PulsePeriod month,
  ) async {
    await controller.setView(PulsePeriodKind.month);
    await controller.selectPeriod(month);
  }

  void _showInfo() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'About these numbers',
                  style: SonusTheme.of(context).text.sectionHeading,
                ),
              ),
              for (final p in PulseOverviewInfo.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(p),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showList(PulsePeriodData data) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${PulseFormat.periodTitle(data.period)} by day',
                  style: SonusTheme.of(context).text.sectionHeading,
                ),
              ),
              const SizedBox(height: 8),
              PulseDayList(data: data),
            ],
          ),
        ),
      ),
    );
  }

  PulseRankingActions _actions(BuildContext context) {
    final playback = context.read<PlaybackCoordinator?>();
    return PulseRankingActions(
      playTracks: playback == null
          ? null
          : (start, tracks) => unawaited(playback.playInContext(start, tracks)),
      openArtist: (id, name) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ArtistProfilePage(artistId: id, initialArtistName: name),
        ),
      ),
      openRelease: (id, title) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AlbumProfilePage(albumId: id, initialAlbumTitle: title),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PulseInsightsController?>();
    final theme = SonusTheme.of(context);
    final gutter = theme.metrics.pageGutter;

    if (controller == null) {
      return const SonusStateView(
        key: ValueKey('pulse-unavailable'),
        icon: Icons.insights_rounded,
        title: 'Insights aren’t available right now',
      );
    }

    final data = controller.data;
    _trackPeriod(controller.isShowingSelectedPeriod ? data?.period : null);
    if (data != null && controller.isShowingSelectedPeriod) {
      _loadRecap(data.period);
    }

    final highContrast =
        context.watch<AppearanceController?>()?.spec.highContrast ??
        MediaQuery.highContrastOf(context);

    return ListenableBuilder(
      listenable: _accent,
      builder: (context, _) {
        final palette = PulsePalette.resolve(
          colors: theme.colors,
          decoration: theme.decoration,
          highContrast: highContrast,
          artwork: _focus == null ? null : _accent.artwork,
        );
        final basePalette = _focus == null
            ? palette
            : PulsePalette.resolve(
                colors: theme.colors,
                decoration: theme.decoration,
                highContrast: highContrast,
              );
        return LayoutBuilder(
          builder: (context, constraints) {
            final header = _Header(
              controller: controller,
              palette: basePalette,
            );
            final status = controller.status;
            final body = switch (status) {
              PulseViewStatus.initializing || PulseViewStatus.loading => [
                const SizedBox(height: 32),
                const SonusStateView.loading(
                  key: ValueKey('pulse-loading'),
                  label: 'Loading your listening',
                ),
              ],
              PulseViewStatus.noHistory => [
                const SizedBox(height: 32),
                const SonusStateView(
                  key: ValueKey('pulse-no-history'),
                  icon: Icons.graphic_eq_rounded,
                  title: 'Listen to something and your Pulse starts here.',
                ),
              ],
              PulseViewStatus.error when data == null => [
                const SizedBox(height: 32),
                SonusStateView(
                  key: const ValueKey('pulse-error'),
                  icon: Icons.error_outline_rounded,
                  isError: true,
                  title:
                      'Your listening couldn’t be loaded. Nothing was changed.',
                  action: FilledButton(
                    onPressed: () => unawaited(controller.retry()),
                    child: const Text('Try again'),
                  ),
                ),
              ],
              _ => null,
            };
            if (body != null || data == null) {
              return ListView(
                key: const ValueKey('pulse-page'),
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 40),
                children: [header, ...?body],
              );
            }

            final wide = constraints.maxWidth >= 720;
            final hero = _heroSection(context, controller, data, palette);
            final rest = _restSections(
              context,
              controller,
              data,
              basePalette,
              palette,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: constraints.maxWidth * 0.4,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(gutter, 12, gutter / 2, 40),
                      children: [header, hero],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('pulse-page'),
                      padding: EdgeInsets.fromLTRB(gutter / 2, 12, gutter, 40),
                      children: rest,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              key: const ValueKey('pulse-page'),
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 40),
              children: [header, hero, ...rest],
            );
          },
        );
      },
    );
  }

  Widget _heroSection(
    BuildContext context,
    PulseInsightsController controller,
    PulsePeriodData data,
    PulsePalette palette,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.error != null)
          _ErrorBanner(onRetry: () => unawaited(controller.retry())),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PulseHero(
              key: const ValueKey('pulse-hero'),
              data: data,
              measure: controller.measure,
              palette: palette,
              comparison: controller.isShowingSelectedPeriod
                  ? controller.comparison
                  : null,
              item: _focus,
              onOpenMonth: (month) => unawaited(_openMonth(controller, month)),
              onShowList: () => _showList(data),
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            key: const ValueKey('pulse-show-list'),
            onPressed: () => _showList(data),
            icon: const Icon(Icons.list_rounded),
            label: const Text('Show as list'),
          ),
        ),
        // An empty period: the hero's readout already says "No
        // listening recorded in …" under a ring of zero dots.
      ],
    );
  }

  List<Widget> _restSections(
    BuildContext context,
    PulseInsightsController controller,
    PulsePeriodData data,
    PulsePalette palette,
    PulsePalette accentPalette,
  ) {
    const gap = SizedBox(height: 16);
    final empty = controller.status == PulseViewStatus.empty;
    final comparison = controller.comparison;
    final isYear = data.period.kind == PulsePeriodKind.year;
    final cards = empty
        ? const <Widget>[]
        : [
            for (final kind in const [
              PulseEntityKind.artist,
              PulseEntityKind.track,
              PulseEntityKind.release,
            ]) ...[
              gap,
              PulseRankingCard(
                key: ValueKey('pulse-card-${kind.name}'),
                kind: kind,
                data: data,
                directory: controller.directory,
                palette: palette,
                accent: _accent,
                comparisonData: controller.comparisonData,
                comparisonTitle: comparison == null
                    ? null
                    : PulseFormat.periodTitle(comparison.period),
                focus: _focus,
                onFocusChanged: _setFocus,
                lifetimeStreams: controller.lifetimeStreams,
                actions: _actions(context),
                artworkPalette: SonusArtworkPalette.shared,
              ),
            ],
          ];
    return [
      gap,
      PulseComparisonChips(
        period: data.period,
        choice: controller.comparisonChoice,
        previous: data.previous,
        samePeriodLastYear: data.samePeriodLastYear,
        firstHistoryAt: data.firstHistoryAt,
        palette: palette,
        onChanged: controller.setComparison,
      ),
      gap,
      PulseOverviewGrid(
        overview: data.overview,
        deltas: PulseOverviewDeltas.of(data.overview, comparison),
        palette: palette,
        onInfo: _showInfo,
      ),
      gap,
      PulseMoreStats(
        key: ValueKey('pulse-more-${data.period}'),
        data: data,
        palette: palette,
      ),
      if (isYear) ...[
        gap,
        PulseMonthsCard(
          data: data,
          measure: controller.measure,
          palette: palette,
          nowLocal: (widget.nowLocal ?? DateTime.now)(),
          onOpenMonth: (m) => unawaited(_openMonth(controller, m)),
        ),
        gap,
        PulseMilestonesCard(data: data, palette: palette, recap: _recap),
      ],
      ...cards,
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.palette});

  final PulseInsightsController controller;
  final PulsePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    final colors = theme.colors;
    final period = controller.selectedPeriod;
    final data = controller.data;
    final first = controller.firstHistoryAt?.toLocal();
    final historyCaption =
        data != null &&
            controller.isShowingSelectedPeriod &&
            data.startsBeforeHistory &&
            first != null
        ? 'History starts ${first.day} ${PulseFormat.shortMonth(first.month)} '
              '${first.year}'
        : null;
    final hasHistory = controller.status != PulseViewStatus.noHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Sonus Pulse', style: theme.text.pageTitle),
        ),
        const SizedBox(height: 10),
        SonusSegmentedSelector<PulsePeriodKind>(
          key: const ValueKey('pulse-view-selector'),
          segments: const [
            SonusSegment(
              value: PulsePeriodKind.month,
              icon: Icons.calendar_view_month_rounded,
              label: 'Month',
            ),
            SonusSegment(
              value: PulsePeriodKind.year,
              icon: Icons.calendar_today_rounded,
              label: 'Year',
            ),
          ],
          selected: period.kind,
          onChanged: (kind) => unawaited(controller.setView(kind)),
        ),
        if (hasHistory) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                key: const ValueKey('pulse-previous'),
                tooltip: 'Previous',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: controller.canGoPrevious
                    ? () => unawaited(controller.previousPeriod())
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  header: true,
                  child: Column(
                    children: [
                      Text(
                        PulseFormat.periodTitle(period),
                        key: const ValueKey('pulse-period-title'),
                        textAlign: TextAlign.center,
                        style: theme.text.sectionHeading,
                      ),
                      if (historyCaption != null)
                        Text(
                          historyCaption,
                          key: const ValueKey('pulse-history-caption'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('pulse-next'),
                tooltip: 'Next',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: controller.canGoNext
                    ? () => unawaited(controller.nextPeriod())
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SonusSegmentedSelector<PulseMeasure>(
            key: const ValueKey('pulse-measure-selector'),
            segments: const [
              SonusSegment(value: PulseMeasure.minutes, label: 'Minutes'),
              SonusSegment(value: PulseMeasure.streams, label: 'Streams'),
            ],
            selected: controller.measure,
            onChanged: controller.setMeasure,
          ),
          if (controller.isLoading && data != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    return Container(
      key: const ValueKey('pulse-error-banner'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.raisedSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Your listening couldn’t be loaded. Nothing was changed.',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
