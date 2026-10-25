import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import 'monthly_listening_insights_page.dart';
import 'year_in_sonus_page.dart';

enum _InsightsView { monthly, year }

class ListeningInsightsPage extends StatefulWidget {
  const ListeningInsightsPage({super.key});

  @override
  State<ListeningInsightsPage> createState() => _ListeningInsightsPageState();
}

class _ListeningInsightsPageState extends State<ListeningInsightsPage> {
  _InsightsView _view = _InsightsView.monthly;

  @override
  Widget build(BuildContext context) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 4),
            child: SizedBox(
              width: double.infinity,
              // The shared Sonus selector: themed locally, drops decorative
              // icons with large text and keeps the selection checkmark.
              child: SonusSegmentedSelector<_InsightsView>(
                key: const ValueKey<String>('listening-insights-view-selector'),
                segments: const [
                  SonusSegment(
                    value: _InsightsView.monthly,
                    icon: Icons.query_stats_rounded,
                    label: 'Monthly',
                  ),
                  SonusSegment(
                    value: _InsightsView.year,
                    icon: Icons.auto_awesome_rounded,
                    label: 'Year',
                  ),
                ],
                selected: _view,
                onChanged: (view) {
                  setState(() {
                    _view = view;
                  });
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            children: const [MonthlyListeningInsightsPage(), YearInSonusPage()],
          ),
        ),
      ],
    );
  }
}
