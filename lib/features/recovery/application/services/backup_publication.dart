import 'dart:io';

import 'package:flutter/services.dart';

import '../models/backup_failure.dart';

/// Publishes a complete, verified file under its final name without ever
/// replacing an existing file.
abstract interface class BackupPublication {
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  });
}

/// Production publication.
///
/// Android publishes through a hard link (`Os.link`), which the kernel
/// rejects with EEXIST instead of replacing a destination. Every other
/// platform fails closed because no equivalent guarantee is available.
class PlatformBackupPublication implements BackupPublication {
  const PlatformBackupPublication({
    this.channel = const MethodChannel(channelName),
    this.isAndroid = _platformIsAndroid,
  });

  static const channelName = 'com.sonus.sonus_next/backup_publication';

  final MethodChannel channel;
  final bool Function() isAndroid;

  static bool _platformIsAndroid() => Platform.isAndroid;

  @override
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  }) async {
    if (!isAndroid()) {
      throw UnsupportedError(
        'Atomic no-replace backup publication is unavailable on this '
        'platform.',
      );
    }

    try {
      await channel.invokeMethod<void>('publishNoReplace', {
        'source': source.path,
        'destination': destination.path,
      });
    } on PlatformException catch (error) {
      if (error.code == 'DESTINATION_EXISTS') {
        throw BackupDestinationExistsError();
      }

      throw BackupException(
        BackupFailureCode.publicationFailed,
        'Atomic backup publication failed.',
      );
    } on MissingPluginException {
      throw BackupException(
        BackupFailureCode.publicationFailed,
        'Atomic backup publication is unavailable.',
      );
    }
  }
}
