import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:saf/saf.dart';

import '../../application/services/import_source_picker.dart';

class FilePickerImportSourcePicker implements ImportSourcePicker {
  FilePickerImportSourcePicker({Saf? saf}) : _saf = saf ?? Saf();

  final Saf _saf;

  @override
  Future<String?> pickSongFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );

    final path = file?.path?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }

  @override
  Future<String?> pickStructuredFolder() async {
    if (Platform.isAndroid) {
      final directory = await _saf.pickDirectory(
        writePermission: false,
        persistablePermission: true,
      );

      final uri = directory?.uri.trim();

      if (uri == null || uri.isEmpty) {
        return null;
      }

      return uri;
    }

    final path = await FilePicker.getDirectoryPath();
    final trimmedPath = path?.trim();

    if (trimmedPath == null || trimmedPath.isEmpty) {
      return null;
    }

    return trimmedPath;
  }
}
