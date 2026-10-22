import 'dart:io';

import 'package:flutter/services.dart';

import '../models/backup_failure.dart';
import 'rename_no_replace_publication.dart';

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
/// Uses the kernel's atomic `renameat2(RENAME_NOREPLACE)` (Android 11+).
/// Every other platform or older Android version fails closed, because no
/// equivalent guarantee is available.
class PlatformBackupPublication implements BackupPublication {
  const PlatformBackupPublication({
    this.delegate = const RenameNoReplacePublication(),
  });

  final BackupPublication delegate;

  @override
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  }) => delegate.publishNoReplace(source: source, destination: destination);
}

/// Hard-link publication through `MainActivity` (`Os.link`).
///
/// NOT used in production: Android 10+ SELinux policy denies `link()` on
/// app data files to apps (EACCES, verified on an API 34 emulator), so it
/// cannot publish there. Kept only with its channel contract tests.
class HardLinkChannelPublication implements BackupPublication {
  const HardLinkChannelPublication({
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
        error.message ?? 'Atomic backup publication failed.',
      );
    } on MissingPluginException {
      throw BackupException(
        BackupFailureCode.publicationFailed,
        'Atomic backup publication is unavailable.',
      );
    }
  }
}
