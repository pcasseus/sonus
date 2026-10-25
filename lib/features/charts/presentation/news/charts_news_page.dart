import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../controllers/charts_controller.dart';
import '../formatters/chart_moment_feed_copy_formatter.dart';
import 'sonus_news_feed_view.dart';
import 'sonus_news_story.dart';

/// Sonus News (Sonus Daily and PulsePop) as opened from Charts.
///
/// It shows the Charts controller's own Chart Moments, so the stories are
/// always the Moments the Charts page has, with the same copy and artwork,
/// and pull-to-refresh is the Charts refresh. It reads only: Moments are
/// never detected, written or recalculated here. Moments describe weekly
/// charts, and every story is labelled with its weekly scope by the shared
/// copy formatter, never as an all-time ranking.
class ChartsNewsPage extends StatelessWidget {
  const ChartsNewsPage({super.key, required this.controller});

  final ChartsController controller;

  static const _formatter = ChartMomentFeedCopyFormatter();

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('charts-news-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Sonus News'),
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.hasMomentFeedError && !controller.hasMomentFeedItems) {
            return SonusStateView(
              key: const ValueKey<String>('charts-news-error'),
              icon: Icons.error_outline_rounded,
              isError: true,
              title: 'Could not load Sonus News.',
              action: FilledButton.tonalIcon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            );
          }

          if (controller.isLoading && !controller.hasMomentFeedItems) {
            return const SonusStateView.loading();
          }

          final stories = SonusNewsDesk(
            copyFor: _formatter.format,
            artworkFor: controller.artworkPathForMoment,
            relatedArtworkFor: controller.relatedArtworkPathForMoment,
          ).stories(controller.momentFeedItems);

          return SonusNewsFeedView(
            stories: stories,
            onRefresh: controller.refresh,
          );
        },
      ),
    );
  }
}
