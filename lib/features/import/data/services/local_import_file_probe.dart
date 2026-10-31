import 'dart:io';

import 'package:saf/saf.dart';

import '../../domain/services/import_file_probe.dart';

/// Checks a plain path with [File.exists] and an Android content URI with
/// the SAF v2 [Saf.exists]. Read-only: it never deletes, moves, renames or
/// writes anything.
class LocalImportFileProbe implements ImportFileProbe {
  const LocalImportFileProbe({this.saf});

  final Saf? saf;

  @override
  Future<ImportFileState> probe(String filePath) async {
    final source = filePath.trim();

    try {
      if (!source.startsWith('content://')) {
        return await File(source).exists()
            ? ImportFileState.present
            : ImportFileState.missing;
      }

      final safInstance = saf;
      if (safInstance == null) return ImportFileState.unknown;

      if (await safInstance.exists(source)) return ImportFileState.present;

      // A folder whose grant was revoked can look empty; only a URI still
      // covered by a read permission is really missing.
      final permissions = await safInstance.persistedPermissions();
      final covered = permissions.any(
        (permission) => permission.read && source.startsWith(permission.uri),
      );
      return covered ? ImportFileState.missing : ImportFileState.permissionLost;
    } on SafPermissionException {
      return ImportFileState.permissionLost;
    } on SafNotFoundException {
      return ImportFileState.missing;
    } catch (_) {
      return ImportFileState.unknown;
    }
  }
}
