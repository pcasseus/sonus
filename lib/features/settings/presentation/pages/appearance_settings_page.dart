import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_theme_id.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../../../core/design/sonus_typography.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../application/controllers/appearance_controller.dart';
import '../widgets/appearance/appearance_preview.dart';
import '../widgets/appearance/appearance_schedule_section.dart';
import '../widgets/appearance/appearance_theme_tile.dart';

/// Theme, typography, decoration, accessibility and scheduling choices.
///
/// Every change applies immediately across Sonus and is saved on this
/// device.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();

    return Scaffold(
      key: const ValueKey<String>('appearance-settings-page'),
      appBar: AppBar(title: const Text('Appearance')),
      body: controller == null
          ? const Center(
              key: ValueKey<String>('appearance-unavailable'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Appearance settings are not available.'),
              ),
            )
          : _AppearanceSettingsBody(controller: controller),
    );
  }
}

class _AppearanceSettingsBody extends StatelessWidget {
  const _AppearanceSettingsBody({required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = SonusTheme.of(context).metrics;

    Widget heading(String title) => Padding(
      padding: EdgeInsets.only(top: metrics.spaceXl, bottom: metrics.spaceMd),
      child: SonusSectionHeading(title: title),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        metrics.pageGutter,
        metrics.spaceLg,
        metrics.pageGutter,
        metrics.spaceXl * 2,
      ),
      children: [
        if (controller.saveError != null) const _SaveErrorBanner(),
        heading('Preview'),
        const AppearancePreview(),
        heading('Theme'),
        _ThemeSection(controller: controller),
        heading('Typography'),
        _TypographySection(controller: controller),
        heading('Decoration'),
        _DecorationSection(controller: controller),
        heading('Accessibility & motion'),
        _AccessibilitySection(controller: controller),
        heading('Scheduled themes'),
        AppearanceScheduleSection(controller: controller),
      ],
    );
  }
}

class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      key: const ValueKey<String>('appearance-save-error'),
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Your appearance changes couldn't be saved. They apply until "
                'Sonus restarts.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection({required this.controller});

  /// Fits the longest theme name on one line at 1x text.
  static const double _minTileWidth = 115;

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final metrics = SonusTheme.of(context).metrics;
    final scheduling = controller.preferences.schedule.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scheduling) ...[
          _ScheduleOverrideNotice(controller: controller),
          SizedBox(height: metrics.spaceMd),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // Three across on typical phones, fewer on narrow screens or
            // with large text, so a name like "Monochrome" never breaks
            // mid-word.
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = (constraints.maxWidth / (_minTileWidth * textScale))
                .floor()
                .clamp(1, 3);
            final spacing = metrics.spaceSm;
            const ids = SonusThemeId.values;

            Widget tile(SonusThemeId id) => AppearanceThemeTile(
              themeId: id,
              baseSpec: controller.spec,
              selected: controller.resolved.theme == id,
              onSelected: () {
                unawaited(controller.selectTheme(id));
              },
            );

            // Tiles in a row share the tallest tile's height, so a name
            // that wraps (e.g. "Concrete & Spray") keeps the grid even.
            return Column(
              children: [
                for (var start = 0; start < ids.length; start += columns) ...[
                  if (start > 0) SizedBox(height: spacing),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) SizedBox(width: spacing),
                          Expanded(
                            child: start + column < ids.length
                                ? tile(ids[start + column])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ScheduleOverrideNotice extends StatelessWidget {
  const _ScheduleOverrideNotice({required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final next = controller.resolved.nextTransitionAt;
    final nextText = next == null
        ? 'the next change'
        : formatInstant(context, controller, next);

    if (!controller.overrideActive) {
      return Text(
        'Scheduling is on. Choosing a theme here keeps it until $nextText.',
        key: const ValueKey<String>('appearance-schedule-hint'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Card(
      key: const ValueKey<String>('appearance-override-notice'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Using ${controller.resolved.theme.label} until $nextText, '
              'then the schedule resumes.',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('appearance-clear-override'),
                onPressed: () {
                  unawaited(controller.clearOverride());
                },
                child: const Text('Return to schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypographySection extends StatelessWidget {
  const _TypographySection({required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.preferences.typography;

    return _ChoiceGroup<SonusTypographyPreset>(
      label: 'Typography',
      values: SonusTypographyPreset.values,
      selected: selected,
      labelOf: (preset) => preset.label,
      keyOf: (preset) => 'appearance-typography-${preset.storageKey}',
      onSelected: (preset) {
        unawaited(controller.setTypography(preset));
      },
      help:
          'Changes headings, rankings and featured figures. Song, artist '
          'and album names keep the readable interface font.',
    );
  }
}

class _DecorationSection extends StatelessWidget {
  const _DecorationSection({required this.controller});

  final AppearanceController controller;

  @override
  Widget build(BuildContext context) {
    final spec = controller.spec;
    final limited =
        (spec.lowEffects || spec.highContrast) &&
        controller.preferences.decoration.index >
            SonusDecorationIntensity.subtle.index;

    return _ChoiceGroup<SonusDecorationIntensity>(
      label: 'Decoration',
      values: SonusDecorationIntensity.values,
      selected: controller.preferences.decoration,
      labelOf: (intensity) => intensity.label,
      keyOf: (intensity) => 'appearance-decoration-${intensity.storageKey}',
      onSelected: (intensity) {
        unawaited(controller.setDecoration(intensity));
      },
      help: limited
          ? 'Decoration is limited to Subtle while high contrast or low '
                'effects is on.'
          : 'Marks and textures around headings and featured sections. '
                'Long lists stay plain.',
      helpKey: limited ? 'appearance-decoration-limited' : null,
    );
  }
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.keyOf,
    required this.onSelected,
    required this.help,
    this.helpKey,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final String Function(T value) keyOf;
  final ValueChanged<T> onSelected;
  final String help;
  final String? helpKey;

  @override
  Widget build(BuildContext context) {
    final metrics = SonusTheme.of(context).metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: label,
          container: true,
          child: Wrap(
            spacing: metrics.spaceSm,
            runSpacing: metrics.spaceSm,
            children: [
              for (final value in values)
                ChoiceChip(
                  key: ValueKey<String>(keyOf(value)),
                  label: Text(labelOf(value)),
                  selected: value == selected,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
        ),
        SizedBox(height: metrics.spaceSm),
        Text(
          help,
          key: helpKey == null ? null : ValueKey<String>(helpKey!),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AccessibilitySection extends StatelessWidget {
  const _AccessibilitySection({required this.controller});

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
                  : 'Stronger text, borders and focus outlines in every '
                        'theme.',
            ),
            value: preferences.highContrast,
            onChanged: (value) {
              unawaited(controller.setHighContrast(value));
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
