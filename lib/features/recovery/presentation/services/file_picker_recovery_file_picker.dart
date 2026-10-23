import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:saf/saf.dart';

import '../../../import/presentation/services/file_picker_import_source_picker.dart';
import '../../application/services/recovery_service.dart';

class FilePickerRecoveryFilePicker implements RecoveryFilePicker {
  FilePickerRecoveryFilePicker({Saf? saf})
    : _folderPicker = FilePickerImportSourcePicker(saf: saf);

  final FilePickerImportSourcePicker _folderPicker;

  @override
  Future<File?> pickBackupFile() async {
    // Android providers rarely know the .sonusbackup type, so any file may
    // be chosen; the verifier rejects anything that is not a valid backup.
    final picked = await FilePicker.pickFile(type: FileType.any);
    final filePath = picked?.path?.trim();

    if (filePath == null || filePath.isEmpty) {
      return null;
    }

    return File(filePath);
  }

  @override
  Future<String?> pickMusicFolder() => _folderPicker.pickStructuredFolder();
}
