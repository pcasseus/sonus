import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:saf/saf.dart';

import '../../domain/models/import_candidate.dart';
import '../../domain/services/lyrics_source_reader.dart';

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

    var text = utf8.decode(bytes, allowMalformed: true);

    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final cleaned = text.trim();

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
