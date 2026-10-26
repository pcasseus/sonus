import 'package:flutter/services.dart';

import '../../application/services/device_music_access.dart';

/// Android's audio permission and MediaStore folder listing, through the
/// app's `audio_library` channel.
class MethodChannelDeviceMusicAccess implements DeviceMusicAccess {
  const MethodChannelDeviceMusicAccess({
    this._channel = const MethodChannel('com.sonus.sonus_next/audio_library'),
  });

  final MethodChannel _channel;

  @override
  Future<DeviceMusicPermission> status() async =>
      _permission(await _channel.invokeMethod<String>('status'));

  @override
  Future<DeviceMusicPermission> request() async =>
      _permission(await _channel.invokeMethod<String>('request'));

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<List<DeviceAudioFolder>> audioFolders() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'audioFolders',
    );
    return [
      for (final row in rows ?? const <Map<Object?, Object?>>[])
        if (row['path'] case final String path)
          DeviceAudioFolder(
            path: path,
            audioCount: (row['audioCount'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  static DeviceMusicPermission _permission(String? value) => switch (value) {
    'granted' => DeviceMusicPermission.granted,
    'blocked' => DeviceMusicPermission.blocked,
    _ => DeviceMusicPermission.denied,
  };
}
