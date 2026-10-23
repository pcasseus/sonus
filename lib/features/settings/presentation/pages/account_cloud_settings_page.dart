import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../sync/application/controllers/sync_controller.dart';
import '../../../sync/application/services/automatic_sync_coordinator.dart';
import '../../domain/models/settings_data_coverage.dart';
import '../widgets/settings/settings_account_card.dart';
import '../widgets/settings/settings_section.dart';
import '../widgets/settings/settings_sync_card.dart';

/// The Google account, cloud sync state and an honest description of what
/// sync does and does not cover.
class AccountCloudSettingsPage extends StatelessWidget {
  const AccountCloudSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountController = context.watch<AccountController?>();
    final syncController = context.watch<SyncController?>();
    final coordinator = context.watch<AutomaticSyncCoordinator?>();

    return Scaffold(
      key: const ValueKey<String>('account-cloud-settings-page'),
      appBar: AppBar(title: const Text('Account & Cloud')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SettingsAccountCard(controller: accountController),
          const SizedBox(height: 16),
          SettingsSyncCard(
            accountController: accountController,
            syncController: syncController,
            automaticSyncCoordinator: coordinator,
          ),
          const SizedBox(height: 24),
          const _SyncCoverageSection(),
        ],
      ),
    );
  }
}

class _SyncCoverageSection extends StatelessWidget {
  const _SyncCoverageSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      key: const ValueKey<String>('settings-sync-coverage'),
      title: 'What cloud sync covers',
      footer:
          'Sonus works fully offline. Sync only adds a copy of the items '
          'above to your account; backups cover more (see Your data & '
          'privacy).',
      children: [
        SettingsInfoTile(
          key: const ValueKey<String>('settings-sync-coverage-synced'),
          icon: Icons.cloud_done_outlined,
          title: 'Synced to your account',
          body: SettingsDataCoverage.cloudSynced.join(', '),
        ),
        SettingsInfoTile(
          key: const ValueKey<String>('settings-sync-coverage-device'),
          icon: Icons.smartphone_rounded,
          title: 'Kept on this device',
          body: SettingsDataCoverage.syncKeepsOnDevice.join(', '),
        ),
        SettingsInfoTile(
          key: const ValueKey<String>('settings-sync-coverage-not-synced'),
          icon: Icons.cloud_off_outlined,
          title: 'Not synced',
          body: SettingsDataCoverage.neverSynced.join(', '),
        ),
        const SettingsInfoTile(
          icon: Icons.logout_rounded,
          title: 'Signing out',
          body:
              'Your library, history and playlists stay on this device. '
              'Once this library is connected to a Sonus account, Sonus '
              'will not automatically attach it to a different account.',
        ),
      ],
    );
  }
}
