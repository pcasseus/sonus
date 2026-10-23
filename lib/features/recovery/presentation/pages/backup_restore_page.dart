import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../../../../app/app_restart_scope.dart';
import '../../application/controllers/backup_restore_controller.dart';
import '../../application/models/recovery_overview.dart';
import '../../application/models/recovery_sync_hold.dart';
import '../../application/models/restore_result.dart';
import '../../application/services/backup_document_exporter.dart';
import '../formatters/recovery_messages.dart';

class BackupRestorePage extends StatelessWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackupRestoreController?>();

    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backup & Restore')),
        body: const Center(
          key: ValueKey<String>('recovery-unavailable'),
          child: Text('Backup and restore are not available yet.'),
        ),
      );
    }

    final result = controller.restoreResult;

    if (result != null) {
      return _RestoreCompleteView(result: result);
    }

    if (controller.operation == RecoveryOperation.restoring) {
      return _RestoringView(stage: controller.restoreStage);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.operation == RecoveryOperation.checkingRecovery)
              const LinearProgressIndicator(
                key: ValueKey<String>('recovery-checking'),
              ),
            if (controller.operationError case final error?)
              _MessageCard(
                key: const ValueKey<String>('recovery-error'),
                icon: Icons.error_outline_rounded,
                text: RecoveryMessages.error(error),
                isError: true,
                onDismiss: controller.dismissResults,
              ),
            _SyncHoldCard(controller: controller),
            _BackupCard(controller: controller),
            _RestoreCard(controller: controller),
            _AudioCard(controller: controller),
            _PrivateBackupsCard(controller: controller),
            _HistoryCard(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _SyncHoldCard extends StatelessWidget {
  const _SyncHoldCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final hold = controller.overview?.hold;
    final startupFailed = controller.startupError != null;

    if (hold == null || (!hold.pausesSync && !startupFailed)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    final reasons = <String>[
      if (startupFailed || hold.startupCheckFailed)
        'Sonus could not finish checking for an interrupted restore, so it '
            'cannot confirm that syncing is safe.',
      if (hold.startupCheckPending && !startupFailed)
        'Sonus is still checking for an interrupted restore.',
      if (hold.phase == RecoverySyncHoldPhase.restoring)
        'A restore did not finish.',
      if (hold.phase == RecoverySyncHoldPhase.restoreFailed)
        'A restore failed and Sonus could not confirm the cleanup.',
      for (final finding in hold.findings) RecoveryMessages.finding(finding),
    ];

    return Card(
      key: const ValueKey<String>('recovery-sync-hold'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cloud sync is paused',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sonus paused cloud sync to protect your restored library and '
              'your cloud account from overwriting each other. Your library, '
              'playback, charts, and other offline features keep working.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            Text(
              'Needs attention before sync can resume:',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final (index, reason) in reasons.indexed)
              Padding(
                key: ValueKey<String>('recovery-sync-hold-reason-$index'),
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $reason',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            if (hold.divergedTables.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Changed: ${hold.divergedTables.map(RecoveryMessages.tableName).join(', ')}',
                key: const ValueKey<String>('recovery-sync-hold-tables'),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Sync resumes automatically once Sonus can prove your library '
              'and cloud account are consistent. It cannot be overridden here.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey<String>('recovery-sync-hold-recheck'),
              onPressed: controller.isBusy ? null : controller.recheckSyncHold,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final busy = controller.operation == RecoveryOperation.backingUp;
    final result = controller.backupResult;

    return _SectionCard(
      title: 'Back up',
      icon: Icons.backup_outlined,
      children: [
        const Text(
          'Creates a verified backup of your library, history, charts, '
          'playlists, lyrics, and artwork, then lets you save it outside the '
          'app (for example to Downloads, Drive, or a USB drive) so a new '
          'device can restore it. Audio files are not included.',
        ),
        const SizedBox(height: 12),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            controller.backupStage == null
                ? 'Starting…'
                : RecoveryMessages.backupStage(controller.backupStage!),
            key: const ValueKey<String>('recovery-backup-stage'),
          ),
        ] else
          FilledButton.icon(
            key: const ValueKey<String>('recovery-create-backup'),
            onPressed: controller.isBusy ? null : controller.createBackup,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Create and save backup'),
          ),
        if (result != null) ...[
          const SizedBox(height: 12),
          _ExportOutcomeText(
            key: const ValueKey<String>('recovery-backup-result'),
            result: result.export,
            privateCopyKept: result.privateCopy != null,
          ),
        ],
      ],
    );
  }
}

class _ExportOutcomeText extends StatelessWidget {
  const _ExportOutcomeText({
    super.key,
    required this.result,
    this.privateCopyKept = false,
  });

  final BackupExportResult result;
  final bool privateCopyKept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kept = privateCopyKept
        ? ' A private copy was kept on this device (see Private backups).'
        : '';

    final (text, color) = switch (result.outcome) {
      BackupExportOutcome.verified => (
        'Backup saved and verified. The saved file matches exactly.',
        scheme.primary,
      ),
      BackupExportOutcome.writtenUnverified => (
        '${result.message ?? 'Saved, but it could not be verified.'}$kept',
        scheme.tertiary,
      ),
      BackupExportOutcome.cancelled => (
        'Saving was cancelled. No backup was saved.',
        scheme.onSurfaceVariant,
      ),
      BackupExportOutcome.failed => (
        '${result.message ?? 'The backup could not be saved.'}$kept',
        scheme.error,
      ),
    };

    return Text(text, style: TextStyle(color: color));
  }
}

class _RestoreCard extends StatelessWidget {
  const _RestoreCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;
    final preparing =
        controller.operation == RecoveryOperation.preparingRestore;

    return _SectionCard(
      title: 'Restore',
      icon: Icons.settings_backup_restore_rounded,
      children: [
        const Text(
          'Replaces the library on this device with a backup. Sonus first '
          'creates a verified safety backup when needed, and '
          'nothing changes until you confirm.',
        ),
        const SizedBox(height: 12),
        if (preparing)
          const LinearProgressIndicator(
            key: ValueKey<String>('recovery-preparing-restore'),
          )
        else if (preview == null)
          OutlinedButton.icon(
            key: const ValueKey<String>('recovery-choose-backup'),
            onPressed: controller.isBusy
                ? null
                : controller.chooseBackupToRestore,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Choose a backup file'),
          )
        else
          _RestorePreviewView(controller: controller, preview: preview),
      ],
    );
  }
}

class _RestorePreviewView extends StatelessWidget {
  const _RestorePreviewView({required this.controller, required this.preview});

  final BackupRestoreController controller;
  final RestorePreview preview;

  @override
  Widget build(BuildContext context) {
    final preflight = preview.preflight;
    final plan = preview.plan;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      key: const ValueKey<String>('recovery-restore-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          path.basename(preview.backupFile.path),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          'Created ${RecoveryMessages.dateTime(preflight.backupCreatedAtUtc)}',
        ),
        const SizedBox(height: 8),
        if (!preview.canRestore) ...[
          for (final blocker in preflight.blockers)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${RecoveryMessages.blocker(blocker)}',
                key: ValueKey<String>('recovery-blocker-${blocker.name}'),
                style: TextStyle(color: scheme.error),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey<String>('recovery-cancel-restore'),
            onPressed: controller.cancelRestore,
            child: const Text('Close'),
          ),
        ] else if (plan != null) ...[
          _PlanRow(
            'Songs restored',
            '${plan.table('songs').restoredRows}',
            'recovery-plan-songs',
          ),
          _PlanRow(
            'Listening sessions restored',
            '${plan.table('playback_sessions').restoredRows}',
            'recovery-plan-sessions',
          ),
          _PlanRow(
            'Playlists restored',
            '${plan.table('playlists').restoredRows}',
            'recovery-plan-playlists',
          ),
          _PlanRow(
            'Items removed from this device',
            '${plan.totalRemoved}',
            'recovery-plan-removed',
          ),
          _PlanRow(
            'Songs that will need their audio relinked',
            '${plan.deviceImpact.songsWithoutAudio}',
            'recovery-plan-missing-audio',
          ),
          if (!preflight.isStorageVerified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Free storage could not be checked on this platform.',
                key: const ValueKey<String>('recovery-storage-unverified'),
                style: TextStyle(color: scheme.tertiary),
              ),
            ),
          if (preflight.requiresSyncAssessment)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This library is linked to cloud sync. Sync will stay paused '
                'after the restore until Sonus confirms it is safe.',
                key: ValueKey<String>('recovery-sync-will-pause'),
              ),
            ),
          if (plan.requiresSafetyBackup)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Your current library will first be saved as a private '
                'safety backup on this device.',
                key: ValueKey<String>('recovery-safety-notice'),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const ValueKey<String>('recovery-start-restore'),
                style: FilledButton.styleFrom(backgroundColor: scheme.error),
                onPressed: () => _confirm(context),
                child: const Text('Restore this backup…'),
              ),
              TextButton(
                key: const ValueKey<String>('recovery-cancel-restore'),
                onPressed: controller.cancelRestore,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _RestoreConfirmationDialog(),
    );

    if (confirmed == true) {
      await controller.confirmRestore(acknowledged: true);
    }
  }
}

class _RestoreConfirmationDialog extends StatefulWidget {
  const _RestoreConfirmationDialog();

  @override
  State<_RestoreConfirmationDialog> createState() =>
      _RestoreConfirmationDialogState();
}

class _RestoreConfirmationDialogState
    extends State<_RestoreConfirmationDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('recovery-confirm-dialog'),
      title: const Text('Replace your library?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your current library, history, charts, and playlists on this '
            'device will be replaced by the backup. When needed, Sonus '
            'creates and verifies a safety backup first. If it cannot be created, nothing is replaced.',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const ValueKey<String>('recovery-confirm-acknowledge'),
            contentPadding: EdgeInsets.zero,
            value: _acknowledged,
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
            title: const Text(
              'I understand my current library will be replaced',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('recovery-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('recovery-confirm-replace'),
          onPressed: _acknowledged
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Replace library'),
        ),
      ],
    );
  }
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final audio = controller.overview?.audio;
    final relink = controller.relinkResult;
    final busy = controller.operation == RecoveryOperation.relinking;

    if (audio == null) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Audio files',
      icon: Icons.library_music_outlined,
      children: [
        Text(
          audio.songsWithoutAudio == 0
              ? 'Every song has its audio file on this device.'
              : '${audio.songsWithoutAudio} of ${audio.totalSongs} songs have '
                    'no audio file on this device.',
          key: const ValueKey<String>('recovery-missing-audio'),
        ),
        if (audio.songsWithoutAudio > 0) ...[
          const SizedBox(height: 4),
          const Text(
            'Backups never include audio. Choose the folder holding your '
            'music and Sonus will reconnect matching files to your restored '
            'songs. Nothing new is added and no restored details change.',
          ),
          const SizedBox(height: 8),
          for (final song in audio.sample.take(5))
            Text(
              '• ${song.title} — ${song.artistName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          if (busy)
            const LinearProgressIndicator(
              key: ValueKey<String>('recovery-relinking'),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey<String>('recovery-relink-audio'),
              onPressed: controller.isBusy ? null : controller.relinkAudio,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Relink audio from a folder'),
            ),
        ],
        if (relink != null) ...[
          const SizedBox(height: 8),
          Text(
            'Relinked ${relink.relinked} songs from ${relink.filesScanned} '
            'files. ${relink.missingAfter} songs still need audio.'
            '${relink.failed > 0 ? ' ${relink.failed} files could not be read.' : ''}',
            key: const ValueKey<String>('recovery-relink-result'),
          ),
        ],
      ],
    );
  }
}

class _PrivateBackupsCard extends StatelessWidget {
  const _PrivateBackupsCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final backups = controller.overview?.privateBackups ?? const [];
    final copyResult = controller.copyExportResult;

    return _SectionCard(
      title: 'Private backups on this device',
      icon: Icons.lock_outline_rounded,
      children: [
        const Text(
          'These are stored only inside Sonus on this device. They are lost '
          'if Sonus is uninstalled or the device is reset. Save a copy '
          'outside the app to keep it safe.',
        ),
        const SizedBox(height: 8),
        if (backups.isEmpty)
          const Text(
            'No private backups.',
            key: ValueKey<String>('recovery-no-private-backups'),
          ),
        for (final (index, backup) in backups.indexed)
          ListTile(
            key: ValueKey<String>('recovery-private-backup-$index'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              backup.kind == PrivateBackupKind.safetyBackup
                  ? Icons.shield_outlined
                  : Icons.warning_amber_rounded,
            ),
            title: Text(
              backup.kind == PrivateBackupKind.safetyBackup
                  ? 'Safety backup (before a restore)'
                  : 'Backup not verified off-device',
            ),
            subtitle: Text(
              '${RecoveryMessages.dateTime(backup.modifiedAt)} · '
              '${RecoveryMessages.bytes(backup.byteLength)}',
            ),
            trailing: PopupMenuButton<String>(
              key: ValueKey<String>('recovery-private-backup-menu-$index'),
              enabled: !controller.isBusy,
              onSelected: (action) {
                if (action == 'export') {
                  controller.exportPrivateBackup(backup);
                } else {
                  controller.previewBackup(backup.file);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('Save a copy…')),
                PopupMenuItem(value: 'restore', child: Text('Restore this…')),
              ],
            ),
          ),
        if (copyResult != null) ...[
          const SizedBox(height: 8),
          _ExportOutcomeText(
            key: const ValueKey<String>('recovery-copy-result'),
            result: copyResult,
          ),
        ],
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.controller});

  final BackupRestoreController controller;

  @override
  Widget build(BuildContext context) {
    final history = controller.overview?.history;
    final backup = history?.lastBackup;
    final restore = history?.lastRestore;

    return _SectionCard(
      title: 'Recovery history',
      icon: Icons.history_rounded,
      children: [
        Text(
          backup == null
              ? 'No verified backup has been saved off this device yet.'
              : 'Last verified backup saved off-device: '
                    '${RecoveryMessages.dateTime(backup.createdAtUtc)}',
          key: const ValueKey<String>('recovery-last-backup'),
        ),
        const SizedBox(height: 4),
        Text(
          restore == null
              ? 'No restore has been performed on this device.'
              : 'Last restore: ${RecoveryMessages.dateTime(restore.restoredAtUtc)} · '
                    '${restore.restoredRows} records · '
                    '${restore.songsWithoutAudio} songs needed audio'
                    '${restore.syncHeld ? ' · sync paused' : ''}',
          key: const ValueKey<String>('recovery-last-restore'),
        ),
      ],
    );
  }
}

class _RestoringView extends StatelessWidget {
  const _RestoringView({required this.stage});

  final RestoreStage? stage;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              key: const ValueKey<String>('recovery-restoring'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  stage == null
                      ? 'Starting the restore…'
                      : RecoveryMessages.restoreStage(stage!),
                  key: const ValueKey<String>('recovery-restore-stage'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Keep Sonus open. If the restore is interrupted, your '
                  'library is protected and recovered the next time Sonus '
                  'starts.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreCompleteView extends StatelessWidget {
  const _RestoreCompleteView({required this.result});

  final RestoreResult result;

  @override
  Widget build(BuildContext context) {
    final missing = result.plan.deviceImpact.songsWithoutAudio;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Restore complete'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          key: const ValueKey<String>('recovery-restore-complete'),
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              'Your library was restored from the backup.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (result.safetyBackup != null)
              const Text(
                'Your previous library was saved as a private safety backup '
                'on this device.',
                key: ValueKey<String>('recovery-complete-safety'),
              ),
            if (missing > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$missing songs need their audio relinked. You can do this '
                'from Backup & Restore.',
                key: const ValueKey<String>('recovery-complete-missing-audio'),
              ),
            ],
            if (result.syncHeld) ...[
              const SizedBox(height: 8),
              const Text(
                'Cloud sync is paused until Sonus can confirm your restored '
                'library and cloud account are consistent. Everything else '
                'works normally.',
                key: ValueKey<String>('recovery-complete-sync-held'),
              ),
            ],
            for (final warning in result.cleanupWarnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(warning),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey<String>('recovery-reload-app'),
              onPressed: () => AppRestartScope.restart(context),
              child: const Text('Reload Sonus'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.label, this.value, this.valueKey);

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            key: ValueKey<String>(valueKey),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.text,
    required this.onDismiss,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final VoidCallback onDismiss;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: isError ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(icon),
        title: Text(text),
        trailing: IconButton(
          key: const ValueKey<String>('recovery-dismiss-message'),
          icon: const Icon(Icons.close_rounded),
          onPressed: onDismiss,
        ),
      ),
    );
  }
}
