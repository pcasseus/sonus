import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/data/services/local_lyrics_source_reader.dart';
import 'package:sonus_next/features/import/data/services/lyrics_text_decoder.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

/// App Update 1.3 (REF-1.3-07): lyrics files in the encodings tools write.
Uint8List _utf16(String text, {required bool littleEndian}) {
  final bytes = BytesBuilder()..add(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final unit in text.codeUnits) {
    final low = unit & 0xFF;
    final high = unit >> 8;
    bytes.add(littleEndian ? [low, high] : [high, low]);
  }
  return bytes.toBytes();
}

void main() {
  const lyric = '[00:01.00]Where Are Ü Now\n[00:02.00]Café 🎵';

  test('UTF-8, with or without a byte order mark', () {
    final plain = Uint8List.fromList(utf8.encode(lyric));
    final marked = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...plain]);
    expect(LyricsTextDecoder.decode(plain), lyric);
    expect(LyricsTextDecoder.decode(marked), lyric);
  });

  test('UTF-16 little and big endian, surrogate pairs kept', () {
    expect(LyricsTextDecoder.decode(_utf16(lyric, littleEndian: true)), lyric);
    expect(LyricsTextDecoder.decode(_utf16(lyric, littleEndian: false)), lyric);
  });

  test('a legacy single-byte file keeps its accented letters', () {
    final latin = Uint8List.fromList(latin1.encode('[00:01.00]Où es-tu, Ü'));
    expect(LyricsTextDecoder.decode(latin), '[00:01.00]Où es-tu, Ü');
    expect(LyricsTextDecoder.decode(latin), isNot(contains('\uFFFD')));
  });

  test('empty and odd-length input never throws', () {
    expect(LyricsTextDecoder.decode(Uint8List(0)), '');
    expect(
      LyricsTextDecoder.decode(Uint8List.fromList([0xFF, 0xFE, 0x41])),
      '',
    );
  });

  test('the sidecar reader uses it', () async {
    final reader = LocalLyricsSourceReader.forTesting(
      readContentUri: (_) async => _utf16('  $lyric\n', littleEndian: true),
    );
    final text = await reader.read(
      ImportCandidate(
        filePath: 'song.mp3',
        normalizedPath: 'song.mp3',
        discoveredAt: DateTime(2026),
        lyricsPath: 'content://lyrics/song.lrc',
      ),
    );
    expect(text, lyric);
  });
}
