import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../analytics/presentation/pages/listening_history_page.dart';
import '../../../recovery/application/controllers/backup_restore_controller.dart';
import '../../../recovery/presentation/pages/backup_restore_page.dart';
import '../../../sync/application/controllers/sync_controller.dart';
import '../../../sync/application/services/automatic_sync_coordinator.dart';
import '../../../sync/application/services/sync_network_policy_service.dart';
import '../../application/controllers/appearance_controller.dart';
import 'appearance_settings_page.dart';
import 'blacklisted_songs_page.dart';
import 'metadata_intelligence_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountController = context.watch<AccountController?>();
    final syncController = context.watch<SyncController?>();
    final automaticSyncCoordinator = context.watch<AutomaticSyncCoordinator?>();

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AccountCard(controller: accountController),
          const SizedBox(height: 24),
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _AppearanceCard(),
          const SizedBox(height: 24),
          Text('Sync', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _SyncCard(
            accountController: accountController,
            syncController: syncController,
            automaticSyncCoordinator: automaticSyncCoordinator,
          ),
          const SizedBox(height: 24),
          Text('Listening', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _ListeningCard(),
          const SizedBox(height: 24),
          Text(
            'Metadata Intelligence',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _MetadataIntelligenceCard(),
          const SizedBox(height: 24),
          Text('Library', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _LibraryCard(),
          const SizedBox(height: 24),
          Text(
            'Backup & Restore',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _BackupRestoreCard(),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.accountController,
    required this.syncController,
    required this.automaticSyncCoordinator,
  });

  final AccountController? accountController;
  final SyncController? syncController;
  final AutomaticSyncCoordinator? automaticSyncCoordinator;

  @override
  Widget build(BuildContext context) {
    final accountController = this.accountController;
    final syncController = this.syncController;
    final coordinator = automaticSyncCoordinator;

    if (accountController == null ||
        syncController == null ||
        coordinator == null) {
      return const Card(
        key: ValueKey<String>('settings-sync-unavailable'),
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Cloud sync'),
          subtitle: Text('Cloud sync is not configured for this build.'),
        ),
      );
    }

    if (!accountController.isSignedIn) {
      return const Card(
        key: ValueKey<String>('settings-sync-signed-out'),
        child: ListTile(
          leading: Icon(Icons.cloud_outlined),
          title: Text('Cloud sync'),
          subtitle: Text('Sign in to sync your Sonus library.'),
        ),
      );
    }

    final statusText = _syncStatusText(
      controller: syncController,
      coordinator: coordinator,
    );

    final lastSynced = syncController.lastSuccessfulSync;
    final canSync =
        !syncController.isSyncing && !syncController.hasAccountConflict;

    return Card(
      key: const ValueKey<String>('settings-sync-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  syncController.hasAccountConflict
                      ? Icons.cloud_off_rounded
                      : syncController.isSyncing
                      ? Icons.cloud_sync_rounded
                      : Icons.cloud_done_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cloud sync',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (syncController.isSyncing)
                  const SizedBox(
                    key: ValueKey<String>('settings-sync-progress'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              key: const ValueKey<String>('settings-sync-status'),
            ),
            const SizedBox(height: 16),
            _SyncDetailRow(
              label: 'Last synced',
              value: lastSynced == null ? 'Never' : _formatSyncTime(lastSynced),
              valueKey: 'settings-sync-last-synced',
            ),
            const SizedBox(height: 8),
            _SyncDetailRow(
              label: 'Pending changes',
              value: '${syncController.pendingChanges}',
              valueKey: 'settings-sync-pending',
            ),
            if (syncController.hasAccountConflict) ...[
              const SizedBox(height: 16),
              Text(
                'This local library is connected to a different Sonus '
                'account. Sonus will not automatically attach it to this '
                'account.',
                key: const ValueKey<String>('settings-sync-account-conflict'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ] else if (syncController.isRecoveryHeld) ...[
              const SizedBox(height: 16),
              Text(
                'Cloud sync is paused while Sonus confirms a restored library '
                'is consistent with your cloud account. Open Backup & Restore '
                'for details.',
                key: const ValueKey<String>('settings-sync-recovery-hold'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ] else if (syncController.status == SyncStatus.error) ...[
              const SizedBox(height: 16),
              Text(
                'Sync could not finish. Sonus will try again later.',
                key: const ValueKey<String>('settings-sync-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (coordinator.mobileConsentRequired) ...[
              const SizedBox(height: 16),
              Container(
                key: const ValueKey<String>('settings-sync-mobile-consent'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use mobile data for sync?',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sonus uses Wi-Fi by default. You can allow cloud sync '
                      'over mobile data on this device.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          key: const ValueKey<String>(
                            'settings-sync-allow-mobile',
                          ),
                          onPressed: coordinator.allowMobileDataAndSync,
                          child: const Text('Allow mobile data'),
                        ),
                        OutlinedButton(
                          key: const ValueKey<String>(
                            'settings-sync-deny-mobile',
                          ),
                          onPressed: coordinator.denyMobileData,
                          child: const Text('Wi-Fi only'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Synced with your Sonus account',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Artists')),
                Chip(label: Text('Albums')),
                Chip(label: Text('Editions')),
                Chip(label: Text('Songs')),
                Chip(label: Text('Artwork')),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('settings-sync-now-button'),
              onPressed: canSync ? coordinator.trigger : null,
              icon: syncController.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(syncController.isSyncing ? 'Syncing...' : 'Sync now'),
            ),
          ],
        ),
      ),
    );
  }

  String _syncStatusText({
    required SyncController controller,
    required AutomaticSyncCoordinator coordinator,
  }) {
    if (controller.hasAccountConflict) {
      return 'Account conflict';
    }

    if (controller.isSyncing) {
      return 'Syncing your library...';
    }

    if (controller.isRecoveryHeld) {
      return 'Paused for recovery review';
    }

    if (controller.status == SyncStatus.error) {
      return 'Waiting to retry';
    }

    return switch (coordinator.networkAccess) {
      SyncNetworkAccess.offline => 'Offline',
      SyncNetworkAccess.mobileConsentRequired =>
        'Waiting for mobile data permission',
      SyncNetworkAccess.mobileDenied => 'Waiting for Wi-Fi',
      SyncNetworkAccess.unsupported => 'Waiting for a supported network',
      SyncNetworkAccess.allowed =>
        controller.lastSuccessfulSync == null ? 'Ready to sync' : 'Up to date',
      null =>
        controller.lastSuccessfulSync == null ? 'Ready to sync' : 'Up to date',
    };
  }

  String _formatSyncTime(DateTime timestamp) {
    final local = timestamp.toLocal();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _SyncDetailRow extends StatelessWidget {
  const _SyncDetailRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          key: ValueKey<String>(valueKey),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _MetadataIntelligenceCard extends StatelessWidget {
  const _MetadataIntelligenceCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-metadata-intelligence'),
        leading: const Icon(Icons.auto_awesome_rounded),
        title: const Text('Metadata Intelligence'),
        subtitle: const Text(
          'Control MusicBrainz lookup and Cover Art Archive suggestions.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const MetadataIntelligenceSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-blacklisted-songs'),
        leading: const Icon(Icons.block_rounded),
        title: const Text('Blacklisted songs'),
        subtitle: const Text('Review songs you have excluded from playback.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const BlacklistedSongsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _BackupRestoreCard extends StatelessWidget {
  const _BackupRestoreCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackupRestoreController?>();
    final held =
        controller?.startupError != null ||
        (controller?.overview?.hold.pausesSync ?? false);

    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-backup-restore'),
        leading: Icon(
          held
              ? Icons.cloud_off_rounded
              : Icons.settings_backup_restore_rounded,
        ),
        title: const Text('Backup & Restore'),
        subtitle: Text(
          held
              ? 'Cloud sync is paused for recovery review.'
              : 'Back up your library or restore it on a new device.',
          key: const ValueKey<String>('settings-backup-restore-subtitle'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const BackupRestorePage(),
            ),
          );
        },
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();
    final subtitle = controller == null
        ? 'Themes, typography, decoration and scheduling.'
        : '${controller.resolved.theme.label} · '
              '${controller.preferences.typography.label}';

    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-appearance'),
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Theme & appearance'),
        subtitle: Text(
          subtitle,
          key: const ValueKey<String>('settings-appearance-subtitle'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const AppearanceSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

class _ListeningCard extends StatelessWidget {
  const _ListeningCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-listening-history'),
        leading: const Icon(Icons.history_rounded),
        title: const Text('Listening history'),
        subtitle: const Text(
          'Review your listening sessions and qualified streams.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const ListeningHistoryPage(),
            ),
          );
        },
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.controller});

  final AccountController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller == null) {
      return const Card(
        child: ListTile(
          key: ValueKey<String>('settings-account-unavailable'),
          leading: Icon(Icons.account_circle_outlined),
          title: Text('Google account'),
          subtitle: Text('Account sign-in is not configured for this build.'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (controller.isSignedIn) {
          return _SignedInAccountCard(controller: controller);
        }

        return _SignedOutAccountCard(controller: controller);
      },
    );
  }
}

class _SignedOutAccountCard extends StatelessWidget {
  const _SignedOutAccountCard({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('settings-account-signed-out'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_circle_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Google account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Sign in to connect your Sonus account.'),
            if (controller.hasError) ...[
              const SizedBox(height: 12),
              Text(
                'Sign-in failed. Please try again.',
                key: const ValueKey<String>('settings-account-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('settings-google-sign-in-button'),
              onPressed: controller.isLoading
                  ? null
                  : controller.signInWithGoogle,
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(
                controller.isLoading ? 'Signing in...' : 'Sign in with Google',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInAccountCard extends StatelessWidget {
  const _SignedInAccountCard({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    final user = controller.user!;

    final displayName = user.displayName ?? user.email ?? 'Google account';
    final secondaryText = user.displayName != null && user.email != null
        ? user.email
        : null;

    return Card(
      key: const ValueKey<String>('settings-account-signed-in'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _AccountAvatar(avatarUrl: user.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        key: const ValueKey<String>(
                          'settings-account-display-name',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (secondaryText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          secondaryText,
                          key: const ValueKey<String>('settings-account-email'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (controller.hasError) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Account action failed. Please try again.',
                  key: const ValueKey<String>('settings-account-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('settings-sign-out-button'),
                onPressed: controller.isLoading ? null : controller.signOut,
                icon: controller.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(
                  controller.isLoading ? 'Signing out...' : 'Sign out',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = this.avatarUrl;

    return CircleAvatar(
      key: const ValueKey<String>('settings-account-avatar'),
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      child: avatarUrl == null ? const Icon(Icons.person_rounded) : null,
    );
  }
}
