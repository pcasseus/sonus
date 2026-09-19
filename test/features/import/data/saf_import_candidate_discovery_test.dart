import 'package:flutter_test/flutter_test.dart';
import 'package:saf/saf.dart';

import 'package:sonus_next/features/import/data/services/saf_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_source_discovery_exception.dart';

void main() {
  final discoveredAt = DateTime.utc(2026, 9, 17, 12);

  SafDocumentFile directory(String uri, String name) {
    return SafDocumentFile(
      uri: uri,
      name: name,
      isDir: true,
      length: 0,
      lastModified: 0,
    );
  }

  SafDocumentFile file(String uri, String name) {
    return SafDocumentFile(
      uri: uri,
      name: name,
      isDir: false,
      length: 123,
      lastModified: 0,
      mimeType: 'audio/mpeg',
    );
  }

  Stream<SafWalkEntry> walkEntries(List<SafWalkEntry> entries) async* {
    for (final entry in entries) {
      yield entry;
    }
  }

  test('discovers structured SAF artist album MP3 hierarchy', () async {
    final discovery = SafImportCandidateDiscovery.forTesting(
      walk: (_) => walkEntries([
        SafWalkEntry(
          file: directory('content://artist-b', 'Artist B'),
          relativePath: 'Artist B',
        ),
        SafWalkEntry(
          file: directory('content://album-b', 'Album B'),
          relativePath: 'Artist B/Album B',
        ),
        SafWalkEntry(
          file: file('content://other-song', '01 Other.mp3'),
          relativePath: 'Artist B/Album B/01 Other.mp3',
        ),
        SafWalkEntry(
          file: directory('content://artist-a', 'Artist A'),
          relativePath: 'Artist A',
        ),
        SafWalkEntry(
          file: directory('content://album-a', 'Album A'),
          relativePath: 'Artist A/Album A',
        ),
        SafWalkEntry(
          file: file('content://second-song', '02 Second.mp3'),
          relativePath: 'Artist A/Album A/02 Second.mp3',
        ),
        SafWalkEntry(
          file: file('content://first-song', '01 First.mp3'),
          relativePath: 'Artist A/Album A/01 First.mp3',
        ),
      ]),
    );

    final candidates = await discovery.discoverFolder(
      'content://music-root',
      discoveredAt: discoveredAt,
    );

    expect(candidates, hasLength(3));
    expect(candidates[0].filePath, 'content://first-song');
    expect(candidates[1].filePath, 'content://second-song');
    expect(candidates[2].filePath, 'content://other-song');

    expect(
      candidates.every((candidate) => candidate.discoveredAt == discoveredAt),
      isTrue,
    );

    expect(
      candidates.every(
        (candidate) =>
            candidate.normalizedPath == candidate.filePath.toLowerCase(),
      ),
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

  test('discovers loose SAF album folder containing MP3 file', () async {
    final discovery = SafImportCandidateDiscovery.forTesting(
      walk: (_) => walkEntries([
        SafWalkEntry(
          file: directory('content://artist', 'Rags'),
          relativePath: 'Rags',
        ),
        SafWalkEntry(
          file: file('content://single', 'Hands Up.mp3'),
          relativePath: 'Rags/Hands Up.mp3',
        ),
      ]),
    );

    final candidates = await discovery.discoverFolder(
      'content://music-root',
      discoveredAt: discoveredAt,
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.filePath, 'content://single');
    expect(candidates.single.discoveredAt, discoveredAt);
    expect(candidates.single.structure, ImportCandidateStructure.looseAlbum);
  });
  test(
    'rejects mixed MP3 files and album folders in the same SAF top-level folder',
    () async {
      final discovery = SafImportCandidateDiscovery.forTesting(
        walk: (_) => walkEntries([
          SafWalkEntry(
            file: directory('content://mixed', 'Mixed'),
            relativePath: 'Mixed',
          ),
          SafWalkEntry(
            file: file('content://direct-song', 'Song.mp3'),
            relativePath: 'Mixed/Song.mp3',
          ),
          SafWalkEntry(
            file: directory('content://album', 'Album'),
            relativePath: 'Mixed/Album',
          ),
          SafWalkEntry(
            file: file('content://nested-song', 'Nested.mp3'),
            relativePath: 'Mixed/Album/Nested.mp3',
          ),
        ]),
      );

      await expectLater(
        discovery.discoverFolder('content://music-root'),
        throwsA(
          isA<ImportSourceDiscoveryException>()
              .having(
                (error) => error.type,
                'type',
                ImportSourceDiscoveryFailureType.invalidStructure,
              )
              .having((error) => error.path, 'path', 'Mixed'),
        ),
      );
    },
  );
  test('ignores empty artist and album folders', () async {
    final discovery = SafImportCandidateDiscovery.forTesting(
      walk: (_) => walkEntries([
        SafWalkEntry(
          file: directory('content://empty-artist', 'Empty Artist'),
          relativePath: 'Empty Artist',
        ),
        SafWalkEntry(
          file: directory('content://artist', 'Justin Bieber'),
          relativePath: 'Justin Bieber',
        ),
        SafWalkEntry(
          file: directory('content://empty-album', 'SWAG'),
          relativePath: 'Justin Bieber/SWAG',
        ),
        SafWalkEntry(
          file: directory('content://real-album', 'Purpose'),
          relativePath: 'Justin Bieber/Purpose',
        ),
        SafWalkEntry(
          file: file('content://song', 'Sorry.mp3'),
          relativePath: 'Justin Bieber/Purpose/Sorry.mp3',
        ),
      ]),
    );

    final candidates = await discovery.discoverFolder(
      'content://music-root',
      discoveredAt: discoveredAt,
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.filePath, 'content://song');
  });
  test('rejects file placed directly in SAF root', () async {
    final discovery = SafImportCandidateDiscovery.forTesting(
      walk: (_) => walkEntries([
        SafWalkEntry(
          file: file('content://stray', 'Song.mp3'),
          relativePath: 'Song.mp3',
        ),
      ]),
    );

    await expectLater(
      discovery.discoverFolder('content://music-root'),
      throwsA(
        isA<ImportSourceDiscoveryException>()
            .having(
              (error) => error.type,
              'type',
              ImportSourceDiscoveryFailureType.invalidStructure,
            )
            .having((error) => error.path, 'path', 'Song.mp3'),
      ),
    );
  });

  test('rejects unsupported file inside SAF album folder', () async {
    final discovery = SafImportCandidateDiscovery.forTesting(
      walk: (_) => walkEntries([
        SafWalkEntry(
          file: directory('content://artist', 'Artist'),
          relativePath: 'Artist',
        ),
        SafWalkEntry(
          file: directory('content://album', 'Album'),
          relativePath: 'Artist/Album',
        ),
        SafWalkEntry(
          file: file('content://flac', 'Song.flac'),
          relativePath: 'Artist/Album/Song.flac',
        ),
      ]),
    );

    await expectLater(
      discovery.discoverFolder('content://music-root'),
      throwsA(
        isA<ImportSourceDiscoveryException>()
            .having(
              (error) => error.type,
              'type',
              ImportSourceDiscoveryFailureType.unsupportedFormat,
            )
            .having((error) => error.path, 'path', 'Artist/Album/Song.flac'),
      ),
    );
  });
}
