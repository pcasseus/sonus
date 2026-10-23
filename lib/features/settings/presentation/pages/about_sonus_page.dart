import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_brand_mark.dart';
import '../../data/app_info_service.dart';
import '../widgets/settings/settings_section.dart';
import 'account_cloud_settings_page.dart';
import 'data_privacy_page.dart';
import 'library_settings_page.dart';

/// The Sonus identity, version, licenses and short troubleshooting help.
/// Shows no account identifiers, device paths or other personal data.
class AboutSonusPage extends StatefulWidget {
  const AboutSonusPage({super.key, this.appInfoService});

  /// Overrides the platform version source (tests).
  final AppInfoService? appInfoService;

  @override
  State<AboutSonusPage> createState() => _AboutSonusPageState();
}

class _AboutSonusPageState extends State<AboutSonusPage> {
  SonusAppInfo? _info;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await (widget.appInfoService ?? const AppInfoService()).load();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loaded = true;
    });
  }

  String get _versionText {
    if (!_loaded) return 'Checking…';
    return _info?.displayVersion ?? 'Unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: const ValueKey<String>('about-sonus-page'),
      appBar: AppBar(title: const Text('About Sonus')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Center(
            child: Column(
              children: [
                const ExcludeSemantics(
                  child: SonusBrandMark(
                    key: ValueKey<String>('about-sonus-mark'),
                    concept: SonusBrandConcept.selected,
                    style: SonusBrandMarkStyle.theme,
                    size: 80,
                  ),
                ),
                SizedBox(height: tokens.metrics.spaceMd),
                Text(
                  'Sonus',
                  style: tokens.text.pageTitle.copyWith(
                    color: tokens.colors.textPrimary,
                  ),
                ),
                SizedBox(height: tokens.metrics.spaceXs),
                Text(
                  'Your music, your library, your charts.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.metrics.spaceXl),
          SettingsSection(
            title: 'App',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                subtitle: Text(
                  _versionText,
                  key: const ValueKey<String>('about-version'),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.storage_rounded),
                title: Text('Library database'),
                subtitle: Text(
                  'Schema version ${AppDatabase.databaseVersion}',
                  key: ValueKey<String>('about-database-version'),
                ),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('about-licenses'),
                icon: Icons.description_outlined,
                title: 'Open-source licenses',
                subtitle: 'The software Sonus is built with.',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Sonus',
                  applicationVersion: _info?.displayVersion,
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(8),
                    child: SonusBrandMark(
                      concept: SonusBrandConcept.selected,
                      style: SonusBrandMarkStyle.theme,
                    ),
                  ),
                ),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('about-data-privacy'),
                icon: Icons.privacy_tip_outlined,
                title: 'Your data & privacy',
                subtitle: 'What Sonus stores, backs up and syncs.',
                onTap: () => pushSettingsPage(context, const DataPrivacyPage()),
              ),
            ],
          ),
          SettingsSection(
            title: 'Troubleshooting',
            children: [
              SettingsNavTile(
                key: const ValueKey<String>('about-help-sync'),
                icon: Icons.sync_problem_rounded,
                title: 'Sync is paused or failing',
                subtitle:
                    'See the sync status, network permission and any '
                    'account or recovery hold.',
                onTap: () =>
                    pushSettingsPage(context, const AccountCloudSettingsPage()),
              ),
              SettingsNavTile(
                key: const ValueKey<String>('about-help-playback'),
                icon: Icons.music_off_rounded,
                title: 'Some songs will not play',
                subtitle:
                    'Find songs whose files are missing, blacklisted songs '
                    'and imports that need review.',
                onTap: () =>
                    pushSettingsPage(context, const LibrarySettingsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
