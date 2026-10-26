enum DeviceMusicPermission {
  granted,
  denied,

  /// Denied with "don't ask again": only the app's settings can grant it.
  blocked,
}

/// A folder that directly holds audio files.
class DeviceAudioFolder {
  const DeviceAudioFolder({required this.path, required this.audioCount});

  final String path;
  final int audioCount;
}

/// Read-only access to the device's music through the standard audio
/// permission. Used where the system folder picker cannot open a folder.
abstract interface class DeviceMusicAccess {
  Future<DeviceMusicPermission> status();

  Future<DeviceMusicPermission> request();

  Future<void> openSettings();

  /// Every folder that directly holds audio, by absolute path.
  Future<List<DeviceAudioFolder>> audioFolders();
}
