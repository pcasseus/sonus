import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_surface_card.dart';
import '../../../../account/application/controllers/account_controller.dart';
import '../../../../sync/application/controllers/sync_controller.dart';
import '../../../../sync/application/models/sync_failure.dart';
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
        !syncController.isSyncing &&
        !syncController.hasAccountConflict &&
        !syncController.isAwaitingCloudChoice;

    return SonusSurfaceCard(
      key: const ValueKey<String>('settings-sync-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                syncController.hasAccountConflict || syncController.isPaused
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
          ] else if (syncController.isAwaitingCloudChoice &&
              !syncController.cloudChoiceHasCloudLibrary) ...[
            const SizedBox(height: 16),
            Text(
              'Cloud sync is off for this device. Nothing has been '
              'uploaded.',
              key: const ValueKey<String>('settings-sync-first-upload-choice'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Turning it on sends this library to your account and keeps it '
              'in step with your other devices. Until then, signing in '
              'changes nothing here, and Sonus works fully on this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('settings-sync-start-first-upload'),
              onPressed: syncController.bringCloudLibrary,
              child: const Text('Turn on cloud sync'),
            ),
          ] else if (syncController.isAwaitingCloudChoice) ...[
            const SizedBox(height: 16),
            Text(
              'This account already has a Sonus cloud library. Nothing has '
              'been uploaded or downloaded yet.',
              key: const ValueKey<String>('settings-sync-cloud-choice'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Bring it here to merge it with the library on this device. '
              'To keep this library separate, sign out and use another '
              'account; sync stays paused until you choose.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('settings-sync-bring-cloud-library'),
              onPressed: syncController.bringCloudLibrary,
              child: const Text('Bring it to this device'),
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
          ] else if (syncController.isPaused) ...[
            const SizedBox(height: 16),
            Text(
              SyncFailureKind.cloudNotReady.message,
              key: const ValueKey<String>('settings-sync-paused'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (syncController.failureCode case final code?) ...[
              const SizedBox(height: 4),
              Text(
                'Details: $code',
                key: const ValueKey<String>('settings-sync-error-code'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ] else if (syncController.status == SyncStatus.error) ...[
            const SizedBox(height: 16),
            Text(
              syncController.failureKind?.message ??
                  SyncFailureKind.unknown.message,
              key: const ValueKey<String>('settings-sync-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (syncController.failureCode case final code?) ...[
              const SizedBox(height: 4),
              Text(
                'Details: $code',
                key: const ValueKey<String>('settings-sync-error-code'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
            onPressed: canSync ? () => coordinator.trigger(retry: true) : null,
            icon: syncController.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              syncController.isSyncing
                  ? 'Syncing...'
                  : syncController.isPaused
                  ? 'Retry'
                  : syncController.status == SyncStatus.error
                  ? 'Try again'
                  : 'Sync now',
            ),
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

    if (controller.isPaused) {
      return 'Sync paused';
    }

    if (controller.isAwaitingCloudChoice) {
      return controller.cloudChoiceHasCloudLibrary
          ? 'Waiting for your choice'
          : 'Off on this device';
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
        controller.lastSuccessfulSync == null ? 'Not synced yet' : 'Up to date',
      null =>
        controller.lastSuccessfulSync == null ? 'Not synced yet' : 'Up to date',
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
