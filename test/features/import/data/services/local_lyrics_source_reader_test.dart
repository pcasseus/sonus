import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/data/services/local_lyrics_source_reader.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

void main() {
  test('reads a local UTF-8 LRC sidecar', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_lrc_reader_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final lyricsFile = File(
      '${directory.path}${Platform.pathSeparator}song.lrc',
    );
    await lyricsFile.writeAsString('[00:01.00]Hello');

    final reader = LocalLyricsSourceReader();
    final value = await reader.read(_candidate(lyricsFile.path));

    expect(value, '[00:01.00]Hello');
  });

  test(
    'reads an Android content URI through the injected SAF reader',
    () async {
      String? requestedUri;

      final reader = LocalLyricsSourceReader.forTesting(
        readContentUri: (uri) async {
          requestedUri = uri;
          return Uint8List.fromList(utf8.encode('[00:02.50]Content lyric'));
        },
      );

      final value = await reader.read(_candidate('content://lyrics/song.lrc'));

      expect(requestedUri, 'content://lyrics/song.lrc');
      expect(value, '[00:02.50]Content lyric');
    },
  );

  test('returns null when candidate has no sidecar', () async {
    final reader = LocalLyricsSourceReader();

    final candidate = ImportCandidate(
      filePath: 'song.mp3',
      normalizedPath: 'song.mp3',
      discoveredAt: DateTime(2026),
    );

    expect(await reader.read(candidate), isNull);
  });
}

ImportCandidate _candidate(String lyricsPath) {
  return ImportCandidate(
    filePath: 'song.mp3',
    normalizedPath: 'song.mp3',
    discoveredAt: DateTime(2026),
    lyricsPath: lyricsPath,
  );
}
