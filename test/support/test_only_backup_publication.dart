import 'dart:io';

import 'package:sonus_next/features/recovery/application/models/backup_failure.dart';
import 'package:sonus_next/features/recovery/application/services/backup_publication.dart';

/// TEST ONLY: host-side stand-in for the Android hard-link publication.
///
/// Check-then-rename is NOT atomic: a file created between the check and
/// the rename could be replaced. It exists only so host tests can exercise
/// the backup pipeline and must never be used from `lib/`.
class TestOnlyBackupPublication implements BackupPublication {
  const TestOnlyBackupPublication();

  @override
  Future<void> publishNoReplace({
    required File source,
    required File destination,
  }) async {
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw BackupDestinationExistsError();
    }

    await source.rename(destination.path);
  }
}
