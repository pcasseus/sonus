import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_surface_card.dart';
import '../../application/folders/device_music_folder_tree.dart';
import '../../application/services/device_music_access.dart';

sealed class DeviceMusicFolderChoice {
  const DeviceMusicFolderChoice();
}

final class ChosenDeviceMusicFolder extends DeviceMusicFolderChoice {
  const ChosenDeviceMusicFolder(this.path);

  final String path;
}

/// The person asked for Android's own folder picker instead.
final class UseSystemFolderPicker extends DeviceMusicFolderChoice {
  const UseSystemFolderPicker();
}

/// Browses the folders on this device that hold music and returns the one
/// to import. Reads through the audio permission, so it works where the
/// system folder picker cannot open a folder (such as Download/Music on
/// some devices). Files are only read; nothing is moved or copied.
class DeviceMusicFolderPage extends StatefulWidget {
  const DeviceMusicFolderPage({super.key, required this.access});

  final DeviceMusicAccess access;

  static Future<DeviceMusicFolderChoice?> open(
    BuildContext context,
    DeviceMusicAccess access,
  ) => Navigator.of(context).push<DeviceMusicFolderChoice>(
    MaterialPageRoute(builder: (_) => DeviceMusicFolderPage(access: access)),
  );

  @override
  State<DeviceMusicFolderPage> createState() => _DeviceMusicFolderPageState();
}

enum _Stage { checking, needsPermission, blocked, loading, ready, failed }

class _DeviceMusicFolderPageState extends State<DeviceMusicFolderPage>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.checking;
  List<DeviceMusicFolderNode> _volumes = const [];
  final List<DeviceMusicFolderNode> _trail = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the app's settings page, where access may have been given.
    if (state == AppLifecycleState.resumed && _stage == _Stage.blocked) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final permission = await widget.access.status();
    if (!mounted) return;
    if (permission == DeviceMusicPermission.granted) {
      await _load();
    } else {
      setState(
        () => _stage = _stage == _Stage.blocked
            ? _Stage.blocked
            : _Stage.needsPermission,
      );
    }
  }

  Future<void> _request() async {
    final permission = await widget.access.request();
    if (!mounted) return;
    switch (permission) {
      case DeviceMusicPermission.granted:
        await _load();
      case DeviceMusicPermission.blocked:
        setState(() => _stage = _Stage.blocked);
      case DeviceMusicPermission.denied:
        setState(() => _stage = _Stage.needsPermission);
    }
  }

  Future<void> _load() async {
    setState(() => _stage = _Stage.loading);
    try {
      final volumes = DeviceMusicFolderTree.build(
        await widget.access.audioFolders(),
      );
      if (!mounted) return;
      setState(() {
        _volumes = volumes;
        _trail
          ..clear()
          ..addAll(volumes.length == 1 ? [volumes.single] : const []);
        _stage = _Stage.ready;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'sonus.import',
          context: ErrorDescription('while listing music folders'),
        ),
      );
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  DeviceMusicFolderNode? get _current => _trail.lastOrNull;

  List<DeviceMusicFolderNode> get _visible => _current?.children ?? _volumes;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final current = _current;

    return PopScope(
      canPop: _trail.length <= (_volumes.length == 1 ? 1 : 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_trail.removeLast);
      },
      child: Scaffold(
        key: const ValueKey<String>('device-music-folder-page'),
        backgroundColor: colors.background,
        appBar: AppBar(
          title: Text(current?.name ?? 'Choose a music folder'),
          backgroundColor: colors.background,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(top: false, child: _body(context)),
        bottomNavigationBar: _importBar(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    Widget message({
      required String title,
      required String body,
      Widget? action,
      Key? key,
    }) => ListView(
      key: key,
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
      children: [
        SonusSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      ],
    );

    switch (_stage) {
      case _Stage.checking:
      case _Stage.loading:
        return const Center(
          child: CircularProgressIndicator(
            key: ValueKey<String>('device-music-loading'),
          ),
        );
      case _Stage.needsPermission:
        return message(
          key: const ValueKey<String>('device-music-permission'),
          title: 'Allow Sonus to read your music',
          body:
              'Sonus reads your audio files where they are, to import them. '
              'It does not move, change or copy them, and it cannot see '
              'your photos or other files.',
          action: FilledButton(
            key: const ValueKey<String>('device-music-allow'),
            onPressed: _request,
            child: const Text('Allow music access'),
          ),
        );
      case _Stage.blocked:
        return message(
          key: const ValueKey<String>('device-music-blocked'),
          title: 'Music access is turned off',
          body:
              'Android will not ask again. In Sonus\'s app settings, open '
              'Permissions, then Music and audio, and choose Allow.',
          action: FilledButton(
            key: const ValueKey<String>('device-music-settings'),
            onPressed: widget.access.openSettings,
            child: const Text('Open app settings'),
          ),
        );
      case _Stage.failed:
        return message(
          title: 'Your music folders could not be listed',
          body: 'Try again. Your files have not been changed.',
          action: FilledButton(
            onPressed: _load,
            child: const Text('Try again'),
          ),
        );
      case _Stage.ready:
        if (_volumes.isEmpty) {
          return message(
            key: const ValueKey<String>('device-music-empty'),
            title: 'No music found on this device',
            body:
                'Android has not found any audio files. If your music is '
                'on an SD card or in cloud storage, use Android\'s folder '
                'picker.',
            action: _systemPickerButton(context),
          );
        }
        return _folderList(context);
    }
  }

  Widget _folderList(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;
    final current = _current;
    final folders = _visible;
    final looseSongs = current?.directAudioCount ?? 0;

    return ListView(
      key: const ValueKey<String>('device-music-folders'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            SonusTheme.of(context).metrics.pageGutter,
            8,
            SonusTheme.of(context).metrics.pageGutter,
            8,
          ),
          child: Text(
            current == null || _volumes.contains(current)
                ? 'Open the folder that holds your music.'
                : 'Open a folder, or import this one. Sonus imports the '
                      'artist and album folders inside it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        for (final folder in folders)
          ListTile(
            key: ValueKey<String>('device-music-folder-${folder.path}'),
            minTileHeight: 56,
            leading: Icon(Icons.folder_outlined, color: colors.textSecondary),
            title: Text(
              folder.name,
              style: TextStyle(color: colors.textPrimary),
            ),
            subtitle: Text(
              _songCount(folder.totalAudioCount),
              style: TextStyle(color: colors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => setState(() => _trail.add(folder)),
          ),
        if (looseSongs > 0)
          ListTile(
            minTileHeight: 56,
            leading: Icon(
              Icons.audio_file_outlined,
              color: colors.textSecondary,
            ),
            title: Text(
              '${_songCount(looseSongs)} directly in this folder',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SonusTheme.of(context).metrics.pageGutter,
            vertical: 8,
          ),
          child: _systemPickerButton(context),
        ),
      ],
    );
  }

  /// For music the browser does not show, such as on cloud storage.
  Widget _systemPickerButton(BuildContext context) => TextButton(
    key: const ValueKey<String>('device-music-system-picker'),
    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    onPressed: () => Navigator.of(context).pop(const UseSystemFolderPicker()),
    child: const Text("Use Android's folder picker instead"),
  );

  /// Only inside a folder: the phone or a memory card as a whole is
  /// never imported.
  Widget? _importBar(BuildContext context) {
    final current = _current;
    if (_stage != _Stage.ready || current == null) return null;
    if (_volumes.contains(current)) return null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SonusTheme.of(context).metrics.pageGutter,
          8,
          SonusTheme.of(context).metrics.pageGutter,
          12,
        ),
        child: FilledButton(
          key: const ValueKey<String>('device-music-import'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () =>
              Navigator.of(context).pop(ChosenDeviceMusicFolder(current.path)),
          child: Text(
            'Import "${current.name}" · '
            '${_songCount(current.totalAudioCount)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  static String _songCount(int count) => count == 1 ? '1 song' : '$count songs';
}
