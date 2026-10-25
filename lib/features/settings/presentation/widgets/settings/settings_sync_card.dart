import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_surface_card.dart';
import '../../../../account/application/controllers/account_controller.dart';
import '../../../../sync/application/controllers/sync_controller.dart';
import '../../../../sync/application/services/automatic_sync_coordinator.dart';
import '../../../../sync/application/services/sync_network_policy_service.dart';

/// Cloud sync state and actions for the signed-in account.
class SettingsSyncCard extends StatelessWidget {
  const SettingsSyncCard({
    super.key,
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
      return const SonusSurfaceCard(
        key: ValueKey<String>('settings-sync-unavailable'),
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Cloud sync'),
          subtitle: Text('Cloud sync is not configured for this build.'),
        ),
      );
    }

    if (!accountController.isSignedIn) {
      return const SonusSurfaceCard(
        key: ValueKey<String>('settings-sync-signed-out'),
        padding: EdgeInsets.zero,
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

    return SonusSurfaceCard(
      key: const ValueKey<String>('settings-sync-card'),
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
          Text(statusText, key: const ValueKey<String>('settings-sync-status')),
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
                color: SonusTheme.of(context).colors.raisedSurface,
                borderRadius: BorderRadius.circular(
                  SonusTheme.of(context).metrics.controlRadius,
                ),
                border: Border.all(
                  color: SonusTheme.of(context).colors.divider,
                ),
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
          ] else if (coordinator.networkAccess ==
              SyncNetworkAccess.mobileDenied) ...[
            const SizedBox(height: 16),
            Text(
              'Sync waits for Wi-Fi because mobile data is not allowed on '
              'this device.',
              key: const ValueKey<String>('settings-sync-wifi-only'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey<String>('settings-sync-allow-mobile-later'),
              onPressed: coordinator.allowMobileDataAndSync,
              child: const Text('Allow mobile data'),
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
