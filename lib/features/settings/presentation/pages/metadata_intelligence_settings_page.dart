import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/metadata_intelligence_settings_controller.dart';
import '../widgets/settings/settings_section.dart';

class MetadataIntelligenceSettingsPage extends StatelessWidget {
  const MetadataIntelligenceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MetadataIntelligenceSettingsController?>();

    return Scaffold(
      key: const ValueKey<String>('metadata-intelligence-settings-page'),
      appBar: AppBar(title: const Text('Metadata Intelligence')),
      body: controller == null
          ? const Center(
              key: ValueKey<String>(
                'metadata-intelligence-settings-unavailable',
              ),
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Metadata Intelligence settings are not available.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                SettingsSection(
                  title: 'Online metadata',
                  children: [
                    SwitchListTile(
                      key: const ValueKey<String>(
                        'metadata-intelligence-online-lookup',
                      ),
                      secondary: const Icon(Icons.public_rounded),
                      title: const Text('Online metadata lookup'),
                      subtitle: const Text(
                        'Allow Sonus to search MusicBrainz for metadata matches.',
                      ),
                      value: controller.onlineMetadataLookupEnabled,
                      onChanged: (enabled) {
                        unawaited(
                          controller.setOnlineMetadataLookupEnabled(enabled),
                        );
                      },
                    ),
                  ],
                ),
                const SettingsSection(
                  title: 'Safety',
                  children: [
                    SettingsInfoTile(
                      icon: Icons.verified_user_outlined,
                      title: 'Manual metadata stays protected',
                      body:
                          'External metadata cannot automatically overwrite fields you manually edited or explicitly confirmed.',
                    ),
                    SettingsInfoTile(
                      icon: Icons.fact_check_outlined,
                      title: 'Unknown metadata requires review',
                      body:
                          'Fields without known authority must be explicitly reviewed before external metadata can change them.',
                    ),
                  ],
                ),
                const SettingsSection(
                  title: 'Providers',
                  children: [
                    SettingsInfoTile(
                      icon: Icons.library_music_outlined,
                      title: 'MusicBrainz',
                      body:
                          'Used for artist, album, and track metadata searches.',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
