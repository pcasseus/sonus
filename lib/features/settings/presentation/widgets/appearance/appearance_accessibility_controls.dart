import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/controllers/appearance_controller.dart';

/// High contrast, bold text, reduced motion and low effects, bound to the shared
/// [AppearanceController]. Used by both Appearance and Accessibility so
/// there is one set of preferences, shown in two places.
class AppearanceAccessibilityControls extends StatelessWidget {
  const AppearanceAccessibilityControls({super.key, required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final preferences = controller.preferences;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey<String>('appearance-high-contrast'),
            title: const Text('High contrast'),
            subtitle: Text(
              controller.systemHighContrast
                  ? 'Your device already asks for high contrast, so Sonus '
                        'uses it.'
                  : 'Stronger colours, borders and focus outlines; turns '
                        'off glows and glass.',
            ),
            value: preferences.highContrast,
            onChanged: (value) {
              unawaited(controller.setHighContrast(value));
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey<String>('appearance-bold-text'),
            title: const Text('Bold text'),
            subtitle: Text(
              controller.systemBoldText
                  ? 'Your device already asks for bold text, so Sonus '
                        'uses it.'
                  : 'Heavier text in every theme, without changing colours '
                        'or effects.',
            ),
            value: preferences.boldText,
            onChanged: (value) {
              unawaited(controller.setBoldText(value));
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey<String>('appearance-reduce-motion'),
            title: const Text('Reduce motion'),
            subtitle: Text(
              controller.systemReduceMotion
                  ? 'Your device already asks for reduced motion, so Sonus '
                        'uses it.'
                  : 'Switch screens and themes without animation.',
            ),
            value: preferences.reduceMotion,
            onChanged: (value) {
              unawaited(controller.setReduceMotion(value));
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey<String>('appearance-low-effects'),
            title: const Text('Low effects'),
            subtitle: const Text(
              'Skip glows, gradients and textures on this device.',
            ),
            value: controller.device.lowEffects,
            onChanged: (value) {
              unawaited(controller.setLowEffects(value));
            },
          ),
        ],
      ),
    );
  }
}
