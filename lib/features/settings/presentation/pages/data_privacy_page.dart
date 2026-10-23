import 'package:flutter/material.dart';

import '../../../recovery/presentation/pages/backup_restore_page.dart';
import '../../domain/models/settings_data_coverage.dart';
import '../widgets/settings/settings_section.dart';
import 'metadata_intelligence_settings_page.dart';

/// Where Sonus keeps each kind of data, what backups and cloud sync cover,
/// and the limits worth knowing about. Read-only.
class DataPrivacyPage extends StatelessWidget {
  const DataPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('data-privacy-page'),
      appBar: AppBar(title: const Text('Your data & privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const SettingsSection(
            title: 'On this device',
            children: [
              SettingsInfoTile(
                icon: Icons.smartphone_rounded,
                title: 'Sonus is local-first',
                body:
                    'Your library, history, charts and playlists live in '
                    "Sonus's private storage on this device and work "
                    'without an internet connection.',
              ),
              SettingsInfoTile(
                icon: Icons.audio_file_outlined,
                title: 'Your audio files',
                body:
                    'Sonus plays your files where they are and never '
                    'uploads or changes them. While importing, it may make a '
                    'short-lived copy to read song details, then deletes it.',
              ),
            ],
          ),
          SettingsSection(
            key: const ValueKey<String>('data-privacy-backups'),
            title: 'Backups',
            children: [
              _ListTile(
                key: const ValueKey<String>('data-privacy-in-backups'),
                icon: Icons.inventory_2_outlined,
                title: 'Included',
                items: SettingsDataCoverage.inBackups,
              ),
              _ListTile(
                key: const ValueKey<String>('data-privacy-not-in-backups'),
                icon: Icons.do_not_disturb_on_outlined,
                title: 'Not included',
                items: SettingsDataCoverage.notInBackups,
              ),
              SettingsNavTile(
                key: const ValueKey<String>('data-privacy-open-backup'),
                icon: Icons.settings_backup_restore_rounded,
                title: 'Backup & Restore',
                subtitle: 'Create a backup or restore one on this device.',
                onTap: () =>
                    pushSettingsPage(context, const BackupRestorePage()),
              ),
            ],
          ),
          SettingsSection(
            key: const ValueKey<String>('data-privacy-cloud'),
            title: 'Cloud sync (when signed in)',
            children: [
              _ListTile(
                icon: Icons.cloud_done_outlined,
                title: 'Synced to your account',
                items: SettingsDataCoverage.cloudSynced,
              ),
              _ListTile(
                icon: Icons.cloud_off_outlined,
                title: 'Never synced',
                items: SettingsDataCoverage.neverSynced,
              ),
            ],
          ),
          SettingsSection(
            title: 'Online services',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('data-privacy-metadata'),
                icon: Icons.public_rounded,
                title: 'Metadata Intelligence',
                subtitle:
                    'When on, Sonus searches MusicBrainz and the Cover Art '
                    'Archive using artist, album and song names. Turn it off '
                    'to keep lookups offline.',
                onTap: () => pushSettingsPage(
                  context,
                  const MetadataIntelligenceSettingsPage(),
                ),
              ),
            ],
          ),
          const SettingsSection(
            title: 'Good to know',
            children: [
              SettingsInfoTile(
                icon: Icons.delete_outline_rounded,
                title: 'Private backups',
                body:
                    'Backups kept inside Sonus are removed if Sonus is '
                    'uninstalled. Save a copy elsewhere to keep it safe.',
              ),
              SettingsInfoTile(
                icon: Icons.restore_rounded,
                title: 'Restoring',
                body:
                    'A restore replaces the library on this device after '
                    'you confirm. If this library is linked to a Sonus '
                    'account, cloud sync may pause until Sonus has checked '
                    'that the two still match.',
              ),
              SettingsInfoTile(
                icon: Icons.image_outlined,
                title: 'Artwork locations in backups',
                body:
                    'A backup can record where artwork you added was stored '
                    'on the original device, such as a folder name. The '
                    'artwork itself is included; your audio is not.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A fact row whose body is a list of data categories.
class _ListTile extends StatelessWidget {
  const _ListTile({
    super.key,
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(items.map((item) => '• $item').join('\n')),
    );
  }
}
