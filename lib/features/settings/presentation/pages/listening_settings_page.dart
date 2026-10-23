import 'package:flutter/material.dart';

import '../../../analytics/presentation/pages/listening_history_page.dart';
import '../../../analytics/presentation/pages/monthly_listening_insights_page.dart';
import '../../../analytics/presentation/pages/year_in_sonus_page.dart';
import '../../../charts/presentation/pages/charts_page.dart';
import '../widgets/settings/settings_section.dart';

/// Shortcuts to listening history, insights and personal charts, and how
/// streams are counted. Nothing here edits history or streams.
class ListeningSettingsPage extends StatelessWidget {
  const ListeningSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('listening-settings-page'),
      appBar: AppBar(title: const Text('Listening & Charts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SettingsSection(
            title: 'Your listening',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('settings-listening-history'),
                icon: Icons.history_rounded,
                title: 'Listening history',
                subtitle:
                    'Review your listening sessions and qualified streams.',
                onTap: () =>
                    pushSettingsPage(context, const ListeningHistoryPage()),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('settings-monthly-insights'),
                icon: Icons.insights_rounded,
                title: 'Monthly insights',
                subtitle:
                    'Streams, listening time and your top picks, month by month.',
                onTap: () => pushSettingsPage(
                  context,
                  const _TitledPage(
                    title: 'Monthly insights',
                    child: MonthlyListeningInsightsPage(),
                  ),
                ),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('settings-year-in-sonus'),
                icon: Icons.auto_awesome_outlined,
                title: 'Year in Sonus',
                subtitle: 'Your year of listening, recapped.',
                onTap: () => pushSettingsPage(
                  context,
                  const _TitledPage(
                    title: 'Year in Sonus',
                    child: YearInSonusPage(),
                  ),
                ),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('settings-personal-charts'),
                icon: Icons.leaderboard_outlined,
                title: 'Personal charts',
                subtitle: 'Your Sonus Hot 100, extended standings and Moments.',
                onTap: () => pushSettingsPage(
                  context,
                  const _TitledPage(title: 'Hot 100', child: ChartsPage()),
                ),
              ),
            ],
          ),
          const SettingsSection(
            title: 'How streams are counted',
            footer:
                'History, streams and charts are recorded by Sonus as you '
                'listen. They cannot be edited or backfilled, which keeps '
                'your charts trustworthy.',
            children: [
              SettingsInfoTile(
                icon: Icons.timer_outlined,
                title: 'Qualified streams',
                body:
                    'A play counts after 30 seconds of listening, or half of '
                    'a song shorter than that (at least 5 seconds).',
              ),
              SettingsInfoTile(
                icon: Icons.save_outlined,
                title: 'Where it is kept',
                body:
                    'On this device and in your Sonus backups. Listening '
                    'history and charts are not synced to the cloud.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gives a tab-style page its own app bar when opened from Settings.
class _TitledPage extends StatelessWidget {
  const _TitledPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}
