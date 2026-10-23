import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../player/application/controllers/playback_preferences_controller.dart';
import '../../../player/domain/models/playback_repeat_mode.dart';
import '../widgets/settings/settings_section.dart';

/// Playback preferences Sonus can genuinely honour today, and the built-in
/// behaviour that is not configurable.
class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackPreferencesController?>();

    return Scaffold(
      key: const ValueKey<String>('playback-settings-page'),
      appBar: AppBar(title: const Text('Playback')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (controller == null)
            const Card(
              key: ValueKey<String>('playback-settings-unavailable'),
              child: ListTile(
                leading: Icon(Icons.play_disabled_rounded),
                title: Text('Playback settings are not available.'),
              ),
            )
          else
            _RememberModesSection(controller: controller),
          const SettingsSection(
            title: 'How playback works',
            children: [
              SettingsInfoTile(
                icon: Icons.headphones_rounded,
                title: 'Headphones unplugged',
                body: 'Playback pauses so music never plays out loud.',
              ),
              SettingsInfoTile(
                icon: Icons.phone_in_talk_rounded,
                title: 'Calls and other interruptions',
                body: 'Playback pauses during a call and resumes when it ends.',
              ),
              SettingsInfoTile(
                icon: Icons.block_rounded,
                title: 'Blacklisted and missing songs',
                body:
                    'Songs you blacklisted, or whose files are missing, are '
                    'left out of the queue.',
              ),
              SettingsInfoTile(
                icon: Icons.graphic_eq_rounded,
                title: 'Listening history',
                body:
                    'A play counts as a stream after 30 seconds, or half of '
                    'a shorter song (at least 5 seconds).',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RememberModesSection extends StatelessWidget {
  const _RememberModesSection({required this.controller});

  final PlaybackPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final preferences = controller.preferences;

    return SettingsSection(
      title: 'Shuffle & repeat',
      footer: preferences.rememberShuffleAndRepeat
          ? 'Saved: shuffle ${preferences.shuffleEnabled ? 'on' : 'off'}, '
                'repeat ${_repeatLabel(preferences.repeatMode)}.'
          : 'Off: every launch starts with shuffle and repeat off.',
      children: [
        SwitchListTile(
          key: const ValueKey<String>('playback-remember-shuffle-repeat'),
          // No leading icon: at large text sizes the title needs the width
          // to wrap between words, like the Accessibility switches.
          title: const Text('Remember shuffle and repeat'),
          subtitle: const Text(
            'Start each launch with the shuffle and repeat modes you used '
            'last, until you change them.',
          ),
          value: preferences.rememberShuffleAndRepeat,
          onChanged: controller.isLoaded
              ? (value) {
                  unawaited(controller.setRememberShuffleAndRepeat(value));
                }
              : null,
        ),
        if (controller.saveError != null)
          const ListTile(
            key: ValueKey<String>('playback-save-error'),
            leading: Icon(Icons.error_outline_rounded),
            title: Text(
              "Couldn't save this setting. It applies until Sonus restarts.",
            ),
          ),
      ],
    );
  }

  static String _repeatLabel(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.off => 'off',
    PlaybackRepeatMode.one => 'one song',
    PlaybackRepeatMode.all => 'all',
  };
}
