import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';

void main() {
  test('single-file discovery attaches matching LRC sidecar', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_lrc_single_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final audioFile = File(path.join(directory.path, 'Track.mp3'));
    final lyricsFile = File(path.join(directory.path, 'Track.lrc'));

    await audioFile.writeAsBytes(const [0]);
    await lyricsFile.writeAsString('[00:01.00]Line');

    final candidate = await const FileSystemImportCandidateDiscovery()
        .discoverFile(audioFile.path);

    expect(candidate.lyricsPath, lyricsFile.path);
  });

  test(
    'folder discovery ignores LRC as a candidate and pairs it to MP3',
    () async {
      final root = await Directory.systemTemp.createTemp('sonus_lrc_folder_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final albumDirectory = await Directory(
        path.join(root.path, 'Album'),
      ).create();

      final audioFile = File(path.join(albumDirectory.path, '01 Song.mp3'));
      final lyricsFile = File(path.join(albumDirectory.path, '01 Song.LRC'));

      await audioFile.writeAsBytes(const [0]);
      await lyricsFile.writeAsString('[00:01.00]Line');

      final candidates = await const FileSystemImportCandidateDiscovery()
          .discoverFolder(root.path);

      expect(candidates, hasLength(1));
      expect(candidates.single.filePath, audioFile.path);
      expect(candidates.single.lyricsPath, lyricsFile.path);
      expect(candidates.single.structure, ImportCandidateStructure.looseAlbum);
    },
  );

  test('unmatched LRC sidecar does not attach to a different MP3', () async {
    final root = await Directory.systemTemp.createTemp('sonus_lrc_unmatched_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final albumDirectory = await Directory(
      path.join(root.path, 'Album'),
    ).create();

    final audioFile = File(path.join(albumDirectory.path, 'Song.mp3'));
    final lyricsFile = File(path.join(albumDirectory.path, 'Other.lrc'));

    await audioFile.writeAsBytes(const [0]);
    await lyricsFile.writeAsString('[00:01.00]Other');

    final candidates = await const FileSystemImportCandidateDiscovery()
        .discoverFolder(root.path);

    expect(candidates, hasLength(1));
    expect(candidates.single.lyricsPath, isNull);
  });
}
