import 'dart:typed_data';

/// Bounded, read-only access to one audio file's bytes (BUG-09).
///
/// Reads are ranges, never the whole file at once, so a large file costs
/// only the memory of the range being read. Nothing here can write.
abstract interface class AudioByteSource {
  /// The file's size in bytes.
  Future<int> length();

  /// When the file last changed, if the system says.
  Future<DateTime?> modifiedAt();

  /// Up to [count] bytes from [offset]; fewer only at the end of the file.
  Future<Uint8List> read(int offset, int count);

  /// Releases the file; the source cannot be read afterwards.
  Future<void> close();
}

/// Opens an [AudioByteSource] for a file path or content URI; null when the
/// file cannot be opened.
typedef AudioByteSourceOpener = Future<AudioByteSource?> Function(String path);
