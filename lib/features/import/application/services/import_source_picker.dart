abstract interface class ImportSourcePicker {
  Future<String?> pickSongFile();

  Future<String?> pickStructuredFolder();
}
