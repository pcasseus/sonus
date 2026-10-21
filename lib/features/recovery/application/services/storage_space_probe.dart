import 'dart:io';

import 'package:flutter/services.dart';

/// Reports free space available to the app on the volume holding a path.
abstract interface class StorageSpaceProbe {
  /// Bytes available, or null when the platform cannot report it.
  Future<int?> availableBytes(String path);
}

class StorageSpaceUnavailable implements Exception {
  const StorageSpaceUnavailable(this.message);

  final String message;

  @override
  String toString() => 'StorageSpaceUnavailable: $message';
}

/// Uses Android's `StatFs.availableBytes` through the platform channel.
///
/// Returns null on platforms without the native implementation. On Android
/// a failed query throws, so callers can fail closed.
class PlatformStorageSpaceProbe implements StorageSpaceProbe {
  const PlatformStorageSpaceProbe({
    this.channel = const MethodChannel(channelName),
    this.isAndroid = _platformIsAndroid,
  });

  static const channelName = 'com.sonus.sonus_next/storage';

  final MethodChannel channel;
  final bool Function() isAndroid;

  static bool _platformIsAndroid() => Platform.isAndroid;

  @override
  Future<int?> availableBytes(String path) async {
    if (!isAndroid()) {
      return null;
    }

    try {
      final bytes = await channel.invokeMethod<int>('availableBytes', {
        'path': path,
      });

      if (bytes == null || bytes < 0) {
        throw const StorageSpaceUnavailable('Invalid free-space result.');
      }

      return bytes;
    } on PlatformException catch (error) {
      throw StorageSpaceUnavailable(error.message ?? error.code);
    } on MissingPluginException {
      throw const StorageSpaceUnavailable('Storage query is unavailable.');
    }
  }
}
