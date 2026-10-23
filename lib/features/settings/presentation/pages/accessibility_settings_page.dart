import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/appearance_controller.dart';
import '../widgets/appearance/appearance_accessibility_controls.dart';
import '../widgets/settings/settings_section.dart';
import 'appearance_settings_page.dart';

/// Accessibility preferences. These are the same appearance preferences
/// shown on the Appearance page, not a separate system.
class AccessibilitySettingsPage extends StatelessWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();

    return Scaffold(
      key: const ValueKey<String>('accessibility-settings-page'),
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (controller == null)
            const Card(
              key: ValueKey<String>('accessibility-unavailable'),
              child: ListTile(
                leading: Icon(Icons.accessibility_new_rounded),
                title: Text('Accessibility settings are not available.'),
              ),
            )
          else ...[
            AppearanceAccessibilityControls(controller: controller),
            const SizedBox(height: 24),
          ],
          const SettingsSection(
            title: 'Also follows your device',
            children: [
              SettingsInfoTile(
                icon: Icons.format_size_rounded,
                title: 'Text size',
                body: 'Sonus uses the font size set on your device.',
              ),
              SettingsInfoTile(
                icon: Icons.motion_photos_off_outlined,
                title: 'Remove animations',
                body:
                    "When your device's animation setting is off, Sonus "
                    'reduces motion even if the switch above is off.',
              ),
              SettingsInfoTile(
                icon: Icons.contrast_rounded,
                title: 'High contrast text',
                body:
                    'When your device asks for high contrast, Sonus uses '
                    'its high-contrast colours in every theme.',
              ),
            ],
          ),
          if (controller != null)
            SettingsSection(
              title: 'More',
              children: [
                SettingsNavTile(
                  key: const ValueKey<String>('accessibility-open-appearance'),
                  icon: Icons.palette_outlined,
                  title: 'Theme, typography and decoration',
                  subtitle: 'Choose a calmer theme or turn decoration off.',
                  onTap: () =>
                      pushSettingsPage(context, const AppearanceSettingsPage()),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
