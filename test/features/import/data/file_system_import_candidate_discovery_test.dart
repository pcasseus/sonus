import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_source_discovery_exception.dart';

void main() {
  late Directory temporaryDirectory;

  final discoveredAt = DateTime.utc(2026, 9, 10, 12);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'sonus_import_discovery_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('discovers a single MP3 file', () async {
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}Song.mp3',
    );

    await file.writeAsBytes([1, 2, 3]);

    const discovery = FileSystemImportCandidateDiscovery();

    final candidate = await discovery.discoverFile(
      file.path,
      discoveredAt: discoveredAt,
    );

    expect(candidate.filePath, file.path);
    expect(
      candidate.normalizedPath,
      file.path.trim().replaceAll('\\', '/').toLowerCase(),
    );
    expect(candidate.discoveredAt, discoveredAt);
    expect(candidate.structure, ImportCandidateStructure.singleFile);
  });

  test('rejects missing single file', () async {
    final missingPath =
        '${temporaryDirectory.path}${Platform.pathSeparator}Missing.mp3';

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFile(missingPath),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.sourceMissing,
        ),
      ),
    );
  });

  test('rejects unsupported single file format', () async {
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}Song.flac',
    );

    await file.writeAsBytes([1, 2, 3]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFile(file.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.unsupportedFormat,
        ),
      ),
    );
  });

  test('discovers structured artist album MP3 hierarchy', () async {
    final artistB = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist B'
      '${Platform.pathSeparator}Album B',
    );

    final artistA = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist A'
      '${Platform.pathSeparator}Album A',
    );

    await artistB.create(recursive: true);
    await artistA.create(recursive: true);

    final secondSong = File(
      '${artistA.path}${Platform.pathSeparator}02 Second.mp3',
    );

    final firstSong = File(
      '${artistA.path}${Platform.pathSeparator}01 First.mp3',
    );

    final otherSong = File(
      '${artistB.path}${Platform.pathSeparator}01 Other.mp3',
    );

    await secondSong.writeAsBytes([2]);
    await firstSong.writeAsBytes([1]);
    await otherSong.writeAsBytes([3]);

    const discovery = FileSystemImportCandidateDiscovery();

    final candidates = await discovery.discoverFolder(
      temporaryDirectory.path,
      discoveredAt: discoveredAt,
    );

    expect(candidates, hasLength(3));

    expect(candidates[0].filePath, firstSong.path);
    expect(candidates[1].filePath, secondSong.path);
    expect(candidates[2].filePath, otherSong.path);

    expect(
      candidates[0].metadataFallbackPath,
      path.join('Artist A', 'Album A', '01 First.mp3'),
    );

    expect(
      candidates[1].metadataFallbackPath,
      path.join('Artist A', 'Album A', '02 Second.mp3'),
    );

    expect(
      candidates[2].metadataFallbackPath,
      path.join('Artist B', 'Album B', '01 Other.mp3'),
    );

    expect(
      candidates.every((candidate) => candidate.discoveredAt == discoveredAt),
      isTrue,
    );

    expect(
      candidates.every(
        (candidate) =>
            candidate.structure == ImportCandidateStructure.artistAlbum,
      ),
      isTrue,
    );
  });

  test('discovers loose album folder containing MP3 files', () async {
    final looseAlbum = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Rags',
    );

    await looseAlbum.create();

    final secondSong = File(
      '${looseAlbum.path}${Platform.pathSeparator}02 Another Song.mp3',
    );

    final firstSong = File(
      '${looseAlbum.path}${Platform.pathSeparator}01 Hands Up.mp3',
    );

    await secondSong.writeAsBytes([2]);
    await firstSong.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    final candidates = await discovery.discoverFolder(
      temporaryDirectory.path,
      discoveredAt: discoveredAt,
    );

    expect(candidates, hasLength(2));
    expect(candidates[0].filePath, firstSong.path);
    expect(candidates[1].filePath, secondSong.path);

    expect(
      candidates[0].metadataFallbackPath,
      path.join('Rags', '01 Hands Up.mp3'),
    );

    expect(
      candidates[1].metadataFallbackPath,
      path.join('Rags', '02 Another Song.mp3'),
    );

    expect(
      candidates.every(
        (candidate) =>
            candidate.structure == ImportCandidateStructure.looseAlbum,
      ),
      isTrue,
    );
  });

  test(
    'supports structured artists and loose albums in the same root',
    () async {
      final album = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}Artist'
        '${Platform.pathSeparator}Album',
      );

      final looseAlbum = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}Rags',
      );

      await album.create(recursive: true);
      await looseAlbum.create();

      final structuredSong = File(
        '${album.path}${Platform.pathSeparator}Song.mp3',
      );

      final looseSong = File(
        '${looseAlbum.path}${Platform.pathSeparator}Loose.mp3',
      );

      await structuredSong.writeAsBytes([1]);
      await looseSong.writeAsBytes([2]);

      const discovery = FileSystemImportCandidateDiscovery();

      final candidates = await discovery.discoverFolder(
        temporaryDirectory.path,
        discoveredAt: discoveredAt,
      );

      expect(candidates, hasLength(2));

      expect(
        candidates.map((candidate) => candidate.metadataFallbackPath),
        containsAll([
          path.join('Artist', 'Album', 'Song.mp3'),
          path.join('Rags', 'Loose.mp3'),
        ]),
      );

      final structuredCandidate = candidates.singleWhere(
        (candidate) =>
            candidate.metadataFallbackPath ==
            path.join('Artist', 'Album', 'Song.mp3'),
      );

      final looseCandidate = candidates.singleWhere(
        (candidate) =>
            candidate.metadataFallbackPath == path.join('Rags', 'Loose.mp3'),
      );

      expect(
        structuredCandidate.structure,
        ImportCandidateStructure.artistAlbum,
      );

      expect(looseCandidate.structure, ImportCandidateStructure.looseAlbum);
    },
  );

  test('rejects files placed directly in import root', () async {
    final strayFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}Song.mp3',
    );

    await strayFile.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFolder(temporaryDirectory.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.invalidStructure,
        ),
      ),
    );
  });

  test('rejects unsupported file inside loose album folder', () async {
    final looseAlbum = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Rags',
    );

    await looseAlbum.create();

    final unsupportedFile = File(
      '${looseAlbum.path}${Platform.pathSeparator}Song.flac',
    );

    await unsupportedFile.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFolder(temporaryDirectory.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.unsupportedFormat,
        ),
      ),
    );
  });

  test('rejects unsupported file inside structured album folder', () async {
    final albumDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist'
      '${Platform.pathSeparator}Album',
    );

    await albumDirectory.create(recursive: true);

    final unsupportedFile = File(
      '${albumDirectory.path}${Platform.pathSeparator}Song.flac',
    );

    await unsupportedFile.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFolder(temporaryDirectory.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.unsupportedFormat,
        ),
      ),
    );
  });

  test('ignores empty top-level folder', () async {
    final empty = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Empty',
    );

    await empty.create();

    const discovery = FileSystemImportCandidateDiscovery();

    final candidates = await discovery.discoverFolder(
      temporaryDirectory.path,
      discoveredAt: discoveredAt,
    );

    expect(candidates, isEmpty);
  });

  test('ignores empty album folder', () async {
    final albumDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist'
      '${Platform.pathSeparator}Empty Album',
    );

    await albumDirectory.create(recursive: true);

    const discovery = FileSystemImportCandidateDiscovery();

    final candidates = await discovery.discoverFolder(
      temporaryDirectory.path,
      discoveredAt: discoveredAt,
    );

    expect(candidates, isEmpty);
  });

  test('rejects mixed MP3 files and album folders at top level', () async {
    final topLevel = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Mixed',
    );

    final album = Directory('${topLevel.path}${Platform.pathSeparator}Album');

    await album.create(recursive: true);

    final directSong = File(
      '${topLevel.path}${Platform.pathSeparator}Song.mp3',
    );

    await directSong.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFolder(temporaryDirectory.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.invalidStructure,
        ),
      ),
    );
  });

  test('rejects folders nested beneath album level', () async {
    final tooDeep = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist'
      '${Platform.pathSeparator}Album'
      '${Platform.pathSeparator}Disc 1',
    );

    await tooDeep.create(recursive: true);

    final song = File('${tooDeep.path}${Platform.pathSeparator}Song.mp3');

    await song.writeAsBytes([1]);

    const discovery = FileSystemImportCandidateDiscovery();

    await expectLater(
      discovery.discoverFolder(temporaryDirectory.path),
      throwsA(
        isA<ImportSourceDiscoveryException>().having(
          (error) => error.type,
          'type',
          ImportSourceDiscoveryFailureType.invalidStructure,
        ),
      ),
    );
  });
}
