import 'package:flutter/material.dart';

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
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_InsightsView>(
                key: const ValueKey<String>('listening-insights-view-selector'),
                segments: const [
                  ButtonSegment<_InsightsView>(
                    value: _InsightsView.monthly,
                    icon: Icon(Icons.query_stats_rounded),
                    label: Text('Monthly'),
                  ),
                  ButtonSegment<_InsightsView>(
                    value: _InsightsView.year,
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: Text('Year'),
                  ),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) {
                    return;
                  }

                  setState(() {
                    _view = selection.first;
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
