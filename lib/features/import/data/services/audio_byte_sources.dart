import 'dart:io';
import 'dart:typed_data';

import 'package:saf/saf.dart';

import '../../domain/services/audio_byte_source.dart';

/// Reads a file on the device's file system in ranges, read-only.
class FileAudioByteSource implements AudioByteSource {
  FileAudioByteSource._(this._path, this._file);

  final String _path;
  final RandomAccessFile _file;

  /// Null when the file cannot be opened for reading.
  static Future<AudioByteSource?> open(String path) async {
    try {
      return FileAudioByteSource._(path, await File(path).open());
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<int> length() => _file.length();

  @override
  Future<DateTime?> modifiedAt() async =>
      (await File(_path).lastModified()).toUtc();

  @override
  Future<Uint8List> read(int offset, int count) async {
    await _file.setPosition(offset);
    return _file.read(count);
  }

  @override
  Future<void> close() => _file.close();
}

/// Reads a Storage Access Framework document (`content://`) in ranges,
/// through the system's document provider; it can never write.
class SafAudioByteSource implements AudioByteSource {
  SafAudioByteSource(this._saf, this._uri, {int? knownLength})
    : _length = knownLength;

  final Saf _saf;
  final String _uri;
  int? _length;
  DateTime? _modifiedAt;

  Future<void> _stat() async {
    final stat = await _saf.stat(_uri);
    if (stat == null) {
      throw const FileSystemException('The document no longer exists.');
    }
    _length = stat.length;
    _modifiedAt = DateTime.fromMillisecondsSinceEpoch(
      stat.lastModified,
      isUtc: true,
    );
  }

  @override
  Future<int> length() async {
    if (_length == null) await _stat();
    return _length!;
  }

  @override
  Future<DateTime?> modifiedAt() async {
    if (_modifiedAt == null) await _stat();
    return _modifiedAt;
  }

  @override
  Future<Uint8List> read(int offset, int count) =>
      _saf.readFileBytes(_uri, start: offset, count: count);

  @override
  Future<void> close() async {}
}

/// Opens a byte source for a file path or a `content://` URI.
AudioByteSourceOpener audioByteSourceOpener({Saf? saf}) => (path) async {
  if (path.startsWith('content://')) {
    return saf == null ? null : SafAudioByteSource(saf, path);
  }
  return FileAudioByteSource.open(path);
};
