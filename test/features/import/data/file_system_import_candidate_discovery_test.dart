import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
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
      candidates.every((candidate) => candidate.discoveredAt == discoveredAt),
      isTrue,
    );

    expect(
      candidates.every(
        (candidate) =>
            candidate.normalizedPath ==
            candidate.filePath.trim().replaceAll('\\', '/').toLowerCase(),
      ),
      isTrue,
    );
  });

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

  test('rejects files placed directly in artist folder', () async {
    final artistDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist',
    );

    await artistDirectory.create();

    final strayFile = File(
      '${artistDirectory.path}${Platform.pathSeparator}Song.mp3',
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

  test('rejects unsupported file inside album folder', () async {
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

  test('rejects empty artist folder', () async {
    final artistDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist',
    );

    await artistDirectory.create();

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

  test('rejects empty album folder', () async {
    final albumDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}Artist'
      '${Platform.pathSeparator}Album',
    );

    await albumDirectory.create(recursive: true);

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
