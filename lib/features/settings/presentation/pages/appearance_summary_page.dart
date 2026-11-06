import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../application/controllers/appearance_controller.dart';
import '../../application/services/appearance_summary.dart';
import '../widgets/settings/settings_section.dart';

/// A read-only account of the effective appearance: what is on, where it
/// comes from, and what limits artwork atmospheres. Changes nothing.
class AppearanceSummaryPage extends StatelessWidget {
  const AppearanceSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();

    return Scaffold(
      key: const ValueKey<String>('appearance-summary-page'),
      appBar: AppBar(title: const Text('Appearance summary')),
      body: controller == null
          ? const Center(
              key: ValueKey<String>('appearance-summary-unavailable'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Appearance settings are not available.'),
              ),
            )
          : _SummaryBody(
              summary: AppearanceSummary.of(
                controller,
                SonusTheme.of(context).decoration,
              ),
            ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final AppearanceSummary summary;

  @override
  Widget build(BuildContext context) {
    Widget row(String key, IconData icon, String title, String value) {
      return SettingsInfoTile(
        key: ValueKey<String>('appearance-summary-$key'),
        icon: icon,
        title: title,
        body: value,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SettingsSection(
          title: 'In use now',
          children: [
            row('theme', Icons.palette_outlined, 'Theme', summary.themeLabel),
            row(
              'decoration',
              Icons.auto_awesome_outlined,
              'Decoration',
              summary.decorationLabel,
            ),
            row(
              'high-contrast',
              Icons.contrast_rounded,
              'High contrast',
              summary.highContrast.label,
            ),
            row(
              'bold-text',
              Icons.format_bold_rounded,
              'Bold text',
              summary.boldText.label,
            ),
            row(
              'low-effects',
              Icons.speed_rounded,
              'Low effects',
              summary.lowEffects.label,
            ),
            row(
              'reduce-motion',
              Icons.motion_photos_off_outlined,
              'Reduce motion',
              summary.reduceMotion.label,
            ),
            row(
              'reactivity',
              Icons.album_outlined,
              'Artwork reactivity',
              summary.reactivityLabel,
            ),
          ],
        ),
        SettingsSection(
          title: 'Artwork atmospheres',
          footer:
              "Android's Remove animations setting turns on Reduce motion "
              'in Sonus.',
          children: [
            if (summary.limits.isEmpty)
              const SettingsInfoTile(
                key: ValueKey<String>('appearance-summary-cause-none'),
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing limits them',
                body: AppearanceSummary.unlimitedExplanation,
              )
            else
              for (final limit in summary.limits)
                SettingsInfoTile(
                  key: ValueKey<String>(
                    'appearance-summary-cause-${limit.name}',
                  ),
                  icon: Icons.info_outline_rounded,
                  title: limit.title,
                  body: limit.explanation,
                ),
          ],
        ),
      ],
    );
  }
}
