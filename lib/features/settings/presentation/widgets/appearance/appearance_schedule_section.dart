import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme_id.dart';
import '../../../application/controllers/appearance_controller.dart';
import '../../../application/services/appearance_schedule_resolver.dart'
    show AppearancePhase;
import '../../../domain/models/appearance_preferences.dart';

/// Day and night theme scheduling.
class AppearanceScheduleSection extends StatelessWidget {
  const AppearanceScheduleSection({super.key, required this.controller});

  final AppearanceController controller;

  AppearanceSchedule get _schedule => controller.preferences.schedule;

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey<String>('appearance-schedule-enabled'),
            title: const Text('Schedule day and night themes'),
            subtitle: const Text(
              'Switch themes automatically at times you choose, using this '
              "device's clock.",
            ),
            value: schedule.enabled,
            onChanged: (value) {
              unawaited(
                controller.updateSchedule(schedule.copyWith(enabled: value)),
              );
            },
          ),
          if (schedule.enabled) ...[
            const Divider(height: 1),
            _ThemeChoiceTile(
              key: const ValueKey<String>('appearance-schedule-day-theme'),
              icon: Icons.wb_sunny_outlined,
              title: 'Day theme',
              value: schedule.dayTheme,
              onChanged: (theme) =>
                  controller.updateSchedule(schedule.copyWith(dayTheme: theme)),
            ),
            _TimeChoiceTile(
              key: const ValueKey<String>('appearance-schedule-day-start'),
              title: 'Day starts at',
              value: schedule.dayStartsAt,
              other: schedule.nightStartsAt,
              onChanged: (time) => controller.updateSchedule(
                schedule.copyWith(dayStartsAt: time),
              ),
            ),
            _ThemeChoiceTile(
              key: const ValueKey<String>('appearance-schedule-night-theme'),
              icon: Icons.nightlight_outlined,
              title: 'Night theme',
              value: schedule.nightTheme,
              onChanged: (theme) => controller.updateSchedule(
                schedule.copyWith(nightTheme: theme),
              ),
            ),
            _TimeChoiceTile(
              key: const ValueKey<String>('appearance-schedule-night-start'),
              title: 'Night starts at',
              value: schedule.nightStartsAt,
              other: schedule.dayStartsAt,
              onChanged: (time) => controller.updateSchedule(
                schedule.copyWith(nightStartsAt: time),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  scheduleStatus(context, controller, schedule),
                  key: const ValueKey<String>('appearance-schedule-status'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A sentence describing which scheduled window is active and what happens
/// next.
String scheduleStatus(
  BuildContext context,
  AppearanceController controller,
  AppearanceSchedule schedule,
) {
  final resolved = controller.resolved;
  final next = resolved.nextTransitionAt;
  final nextText = next == null
      ? null
      : formatInstant(context, controller, next);

  return switch (resolved.phase) {
    AppearancePhase.manual => 'Scheduling is off.',
    AppearancePhase.override =>
      'Using ${resolved.theme.label} until $nextText, then the schedule '
          'resumes.',
    AppearancePhase.day =>
      'Day theme active. ${schedule.nightTheme.label} starts at $nextText.',
    AppearancePhase.night =>
      'Night theme active. ${schedule.dayTheme.label} starts at $nextText.',
  };
}

/// [instant] as a wall-clock time in the schedule's zone and the user's
/// 12/24-hour format.
String formatInstant(
  BuildContext context,
  AppearanceController controller,
  DateTime instant,
) {
  final local = controller.toLocalTime(instant);

  return formatClockTime(
    context,
    TimeOfDay(hour: local.hour, minute: local.minute),
  );
}

String formatClockTime(BuildContext context, TimeOfDay time) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    time,
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final SonusThemeId value;
  final Future<void> Function(SonusThemeId theme) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value.label),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final picked = await showModalBottomSheet<SonusThemeId>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) =>
              _ThemeChoiceSheet(title: title, selected: value),
        );

        if (picked != null && picked != value) {
          await onChanged(picked);
        }
      },
    );
  }
}

class _ThemeChoiceSheet extends StatelessWidget {
  const _ThemeChoiceSheet({required this.title, required this.selected});

  final String title;
  final SonusThemeId selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          for (final theme in SonusThemeId.values)
            ListTile(
              key: ValueKey<String>(
                'appearance-schedule-choice-${theme.storageKey}',
              ),
              title: Text(theme.label),
              selected: theme == selected,
              trailing: theme == selected
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.of(context).pop(theme),
            ),
        ],
      ),
    );
  }
}

class _TimeChoiceTile extends StatelessWidget {
  const _TimeChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.other,
    required this.onChanged,
  });

  final String title;
  final AppearanceClockTime value;

  /// The other window's start; the two may not be equal.
  final AppearanceClockTime other;
  final Future<void> Function(AppearanceClockTime time) onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: value.hour, minute: value.minute);

    return ListTile(
      leading: const Icon(Icons.schedule_rounded),
      title: Text(title),
      subtitle: Text(formatClockTime(context, time)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          helpText: title,
        );

        if (picked == null || !context.mounted) {
          return;
        }

        final chosen = AppearanceClockTime(picked.hour, picked.minute);

        if (chosen == other) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Day and night must start at different times.'),
            ),
          );
          return;
        }

        if (chosen != value) {
          await onChanged(chosen);
        }
      },
    );
  }
}
