import 'package:file_picker/file_picker.dart';

import '../../application/services/artwork_file_picker.dart';

class FilePickerArtworkFilePicker implements ArtworkFilePicker {
  const FilePickerArtworkFilePicker();

  @override
  Future<String?> pickArtworkFile() async {
    final file = await FilePicker.pickFile(type: FileType.image);

    final path = file?.path?.trim();

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }
}
