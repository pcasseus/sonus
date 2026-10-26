import '../services/device_music_access.dart';

/// One folder in the device music browser, with the audio below it.
class DeviceMusicFolderNode {
  DeviceMusicFolderNode._(this.path, this.name);

  final String path;
  final String name;
  final List<DeviceMusicFolderNode> children = [];
  int directAudioCount = 0;
  int totalAudioCount = 0;

  bool get hasSubfolders => children.isNotEmpty;
}

/// Builds browsable folder trees from the folders that hold audio, one
/// tree per storage volume. Folders with no audio anywhere below them are
/// left out, so the browser only shows places worth importing from.
abstract final class DeviceMusicFolderTree {
  static const internalStorage = '/storage/emulated/0';

  static List<DeviceMusicFolderNode> build(List<DeviceAudioFolder> folders) {
    final roots = <String, DeviceMusicFolderNode>{};

    for (final folder in folders) {
      final path = _clean(folder.path);
      final volume = _volumeOf(path);
      if (volume == null || folder.audioCount <= 0) continue;

      final root = roots.putIfAbsent(
        volume,
        () => DeviceMusicFolderNode._(volume, volumeName(volume)),
      );
      root.totalAudioCount += folder.audioCount;

      var node = root;
      final relative = path.length > volume.length
          ? path.substring(volume.length + 1)
          : '';
      for (final segment in relative.split('/').where((s) => s.isNotEmpty)) {
        final childPath = '${node.path}/$segment';
        var child = node.children.where((c) => c.path == childPath).firstOrNull;
        if (child == null) {
          child = DeviceMusicFolderNode._(childPath, segment);
          node.children.add(child);
        }
        child.totalAudioCount += folder.audioCount;
        node = child;
      }
      node.directAudioCount += folder.audioCount;
    }

    final result = roots.values.toList()
      ..sort((a, b) {
        if (a.path == internalStorage) return -1;
        if (b.path == internalStorage) return 1;
        return a.path.compareTo(b.path);
      });
    result.forEach(_sort);
    return result;
  }

  static String volumeName(String volume) => volume == internalStorage
      ? 'This phone'
      : 'Storage ${volume.split('/').last}';

  static void _sort(DeviceMusicFolderNode node) {
    node.children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    node.children.forEach(_sort);
  }

  static String _clean(String path) =>
      path.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp('/{2,}'), '/');

  /// `/storage/emulated/0` or a removable volume such as
  /// `/storage/1234-ABCD`; anything else is not browsable.
  static String? _volumeOf(String path) {
    if (path == internalStorage || path.startsWith('$internalStorage/')) {
      return internalStorage;
    }
    final match = RegExp(
      r'^/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}',
    ).firstMatch(path);
    return match?.group(0);
  }
}
