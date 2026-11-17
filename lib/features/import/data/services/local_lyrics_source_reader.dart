import 'dart:io';
import 'dart:typed_data';

import 'package:saf/saf.dart';

import '../../domain/models/import_candidate.dart';
import '../../domain/services/lyrics_source_reader.dart';
import 'lyrics_text_decoder.dart';

typedef ContentUriBytesReader = Future<Uint8List> Function(String uri);

class LocalLyricsSourceReader implements LyricsSourceReader {
  LocalLyricsSourceReader({Saf? saf})
    : _readContentUri = saf == null ? null : ((uri) => saf.readFileBytes(uri));

  LocalLyricsSourceReader.forTesting({required this._readContentUri});

  final ContentUriBytesReader? _readContentUri;

  @override
  Future<String?> read(ImportCandidate candidate) async {
    final source = candidate.lyricsPath?.trim();

    if (source == null || source.isEmpty) {
      return null;
    }

    final bytes = source.startsWith('content://')
        ? await _readSafBytes(source)
        : await File(source).readAsBytes();

    if (bytes.isEmpty) {
      return null;
    }

    // Byte order marks are dropped by the decoder.
    final cleaned = LyricsTextDecoder.decode(bytes).trim();

    if (cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  Future<Uint8List> _readSafBytes(String source) {
    final reader = _readContentUri;

    if (reader == null) {
      throw StateError('SAF access is required to read content URI lyrics.');
    }

    return reader(source);
  }
}
