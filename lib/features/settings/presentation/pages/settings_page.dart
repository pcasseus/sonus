import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_page_header.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../player/application/controllers/playback_preferences_controller.dart';
import '../../../recovery/application/controllers/backup_restore_controller.dart';
import '../../../recovery/presentation/pages/backup_restore_page.dart';
import '../../../sync/application/controllers/sync_controller.dart';
import '../../application/controllers/appearance_controller.dart';
import '../../application/controllers/metadata_intelligence_settings_controller.dart';
import '../widgets/settings/settings_section.dart';
import 'about_sonus_page.dart';
import 'accessibility_settings_page.dart';
import 'account_cloud_settings_page.dart';
import 'appearance_settings_page.dart';
import 'data_privacy_page.dart';
import 'library_settings_page.dart';
import 'listening_settings_page.dart';
import 'metadata_intelligence_settings_page.dart';
import 'playback_settings_page.dart';

/// The Settings landing page: every area of Sonus in a few grouped rows,
/// each with a live one-line summary and its own detail page.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final gutter = tokens.metrics.pageGutter;

    return ColoredBox(
      color: tokens.colors.background,
      child: ListView(
        key: const ValueKey<String>('settings-landing'),
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const SonusPageHeader(
            title: 'Settings',
            padding: EdgeInsets.fromLTRB(0, 20, 0, 18),
          ),
          SettingsSection(
            title: 'Account',
            children: [const _AccountCloudTile()],
          ),
          SettingsSection(
            title: 'Experience',
            children: [
              const _AppearanceTile(),
              const _AccessibilityTile(),
              const _PlaybackTile(),
            ],
          ),
          SettingsSection(
            title: 'Library',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('settings-library'),
                icon: Icons.library_music_outlined,
                title: 'Library & Imports',
                subtitle:
                    'Import music, review imports and find songs that will '
                    'not play.',
                onTap: () =>
                    pushSettingsPage(context, const LibrarySettingsPage()),
              ),
              const _MetadataIntelligenceTile(),
            ],
          ),
          SettingsSection(
            title: 'Listening',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('settings-listening'),
                icon: Icons.insights_rounded,
                title: 'Listening & Charts',
                subtitle: 'History, insights, Year in Sonus and your charts.',
                onTap: () =>
                    pushSettingsPage(context, const ListeningSettingsPage()),
              ),
            ],
          ),
          SettingsSection(
            title: 'Data',
            children: [
              const _BackupRestoreTile(),
              SettingsNavTile(
                key: const ValueKey<String>('settings-data-privacy'),
                icon: Icons.privacy_tip_outlined,
                title: 'Your data & privacy',
                subtitle: 'What Sonus stores, backs up and syncs.',
                onTap: () => pushSettingsPage(context, const DataPrivacyPage()),
              ),
            ],
          ),
          SettingsSection(
            title: 'About',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('settings-about'),
                icon: Icons.info_outline_rounded,
                title: 'About Sonus',
                subtitle: 'Version, licenses and help.',
                onTap: () => pushSettingsPage(context, const AboutSonusPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountCloudTile extends StatelessWidget {
  const _AccountCloudTile();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountController?>();
    final sync = context.watch<SyncController?>();
    final (summary, warning) = accountCloudSummary(account, sync);

    return SettingsNavTile(
      key: const ValueKey<String>('settings-account-cloud'),
      icon: Icons.account_circle_outlined,
      title: 'Account & Cloud',
      subtitle: summary,
      subtitleKey: const ValueKey<String>('settings-account-cloud-subtitle'),
      warning: warning,
      onTap: () => pushSettingsPage(context, const AccountCloudSettingsPage()),
    );
  }
}

/// One line describing the account and sync state, and whether it needs
/// attention.
@visibleForTesting
(String, bool) accountCloudSummary(
  AccountController? account,
  SyncController? sync,
) {
  if (account == null) {
    return ('Sign-in is not configured for this build.', false);
  }

  if (!account.isSignedIn) {
    return ('Not signed in. Sonus works fully offline.', false);
  }

  final user = account.user;
  final name = user?.displayName ?? user?.email ?? 'Google account';

  if (sync == null) {
    return ('Signed in as $name', false);
  }
  if (sync.hasAccountConflict) {
    return ('This library is linked to a different account.', true);
  }
  if (sync.isRecoveryHeld) {
    return ('Cloud sync is paused for recovery review.', true);
  }
  if (sync.status == SyncStatus.error) {
    return ('Sync could not finish. Sonus will try again.', true);
  }
  if (sync.isSyncing) {
    return ('$name · Syncing…', false);
  }

  return (
    sync.lastSuccessfulSync == null
        ? '$name · Not synced yet'
        : '$name · Up to date',
    false,
  );
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();

    return SettingsNavTile(
      key: const ValueKey<String>('settings-appearance'),
      icon: Icons.palette_outlined,
      title: 'Theme & appearance',
      subtitle: controller == null
          ? 'Themes, typography, decoration and scheduling.'
          : '${controller.resolved.theme.label} · '
                '${controller.preferences.typography.label}',
      subtitleKey: const ValueKey<String>('settings-appearance-subtitle'),
      onTap: () => pushSettingsPage(context, const AppearanceSettingsPage()),
    );
  }
}

class _AccessibilityTile extends StatelessWidget {
  const _AccessibilityTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();
    final spec = controller?.spec;
    final active = [
      if (spec?.highContrast ?? false) 'High contrast',
      if (spec?.reduceMotion ?? false) 'Reduced motion',
      if (spec?.lowEffects ?? false) 'Low effects',
    ];

    return SettingsNavTile(
      key: const ValueKey<String>('settings-accessibility'),
      icon: Icons.accessibility_new_rounded,
      title: 'Accessibility',
      subtitle: active.isEmpty
          ? 'Contrast, motion and visual effects.'
          : '${active.join(' · ')} on',
      subtitleKey: const ValueKey<String>('settings-accessibility-subtitle'),
      onTap: () => pushSettingsPage(context, const AccessibilitySettingsPage()),
    );
  }
}

class _PlaybackTile extends StatelessWidget {
  const _PlaybackTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackPreferencesController?>();
    final remember = controller?.preferences.rememberShuffleAndRepeat ?? false;

    return SettingsNavTile(
      key: const ValueKey<String>('settings-playback'),
      icon: Icons.play_circle_outline_rounded,
      title: 'Playback',
      subtitle: remember
          ? 'Remembers shuffle and repeat.'
          : 'Shuffle and repeat, and how playback behaves.',
      subtitleKey: const ValueKey<String>('settings-playback-subtitle'),
      onTap: () => pushSettingsPage(context, const PlaybackSettingsPage()),
    );
  }
}

class _MetadataIntelligenceTile extends StatelessWidget {
  const _MetadataIntelligenceTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MetadataIntelligenceSettingsController?>();
    final String summary;

    if (controller == null || !controller.isLoaded) {
      summary = 'Control MusicBrainz lookup and Cover Art Archive suggestions.';
    } else if (!controller.onlineMetadataLookupEnabled) {
      summary = 'Off. Metadata lookups stay offline.';
    } else if (controller.effectiveCoverArtSuggestionsEnabled) {
      summary = 'On, with cover art suggestions.';
    } else {
      summary = 'On, without cover art suggestions.';
    }

    return SettingsNavTile(
      key: const ValueKey<String>('settings-metadata-intelligence'),
      icon: Icons.auto_awesome_rounded,
      title: 'Metadata Intelligence',
      subtitle: summary,
      subtitleKey: const ValueKey<String>(
        'settings-metadata-intelligence-subtitle',
      ),
      onTap: () =>
          pushSettingsPage(context, const MetadataIntelligenceSettingsPage()),
    );
  }
}

class _BackupRestoreTile extends StatelessWidget {
  const _BackupRestoreTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackupRestoreController?>();
    final held =
        controller?.startupError != null ||
        (controller?.overview?.hold.pausesSync ?? false);

    return SettingsNavTile(
      key: const ValueKey<String>('settings-backup-restore'),
      icon: held
          ? Icons.cloud_off_rounded
          : Icons.settings_backup_restore_rounded,
      title: 'Backup & Restore',
      subtitle: held
          ? 'Cloud sync is paused for recovery review.'
          : 'Back up your library or restore it on a new device.',
      subtitleKey: const ValueKey<String>('settings-backup-restore-subtitle'),
      warning: held,
      onTap: () => pushSettingsPage(context, const BackupRestorePage()),
    );
  }
}
