import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/metadata_intelligence_settings_controller.dart';

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  'Online metadata',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
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
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const ValueKey<String>(
                          'metadata-intelligence-cover-art-suggestions',
                        ),
                        secondary: const Icon(Icons.image_search_rounded),
                        title: const Text('Cover Art Archive suggestions'),
                        subtitle: Text(
                          controller.onlineMetadataLookupEnabled
                              ? 'Allow Sonus to search for album artwork suggestions.'
                              : 'Enable online metadata lookup to use artwork suggestions.',
                        ),
                        value: controller.coverArtSuggestionsEnabled,
                        onChanged: controller.onlineMetadataLookupEnabled
                            ? (enabled) {
                                unawaited(
                                  controller.setCoverArtSuggestionsEnabled(
                                    enabled,
                                  ),
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Safety', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.verified_user_outlined),
                        title: Text('Manual metadata stays protected'),
                        subtitle: Text(
                          'External metadata cannot automatically overwrite fields you manually edited or explicitly confirmed.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.fact_check_outlined),
                        title: Text('Unknown metadata requires review'),
                        subtitle: Text(
                          'Fields without known authority must be explicitly reviewed before external metadata can change them.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Providers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.library_music_outlined),
                        title: Text('MusicBrainz'),
                        subtitle: Text(
                          'Used for artist, album, and track metadata searches.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.photo_library_outlined),
                        title: Text('Cover Art Archive'),
                        subtitle: Text('Used for album artwork suggestions.'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
