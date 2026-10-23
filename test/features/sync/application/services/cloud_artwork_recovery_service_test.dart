import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:sonus_next/features/artwork/application/services/owned_artwork_managed_storage.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artwork_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artwork_storage.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';

void main() {
  late Directory root;
  late Directory downloads;
  late _FakeStorage storage;
  late _FakeManagedStorage managed;
  late List<String> validated;
  late Object? validationError;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_recovery_');
    downloads = await Directory(p.join(root.path, 'downloads')).create();
    storage = _FakeStorage();
    managed = _FakeManagedStorage(p.join(root.path, 'managed'));
    validated = [];
    validationError = null;
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  CloudArtworkRecoveryService service() {
    return CloudArtworkRecoveryService(
      cloudArtworkStorage: storage,
      managedStorage: managed,
      validateImage: (path) async {
        validated.add(path);

        final error = validationError;

        if (error != null) {
          throw error;
        }
      },
      downloadDirectory: () async => downloads.path,
      maxBytes: 4096,
    );
  }

  CloudArtworkAssetRecord record({DateTime? deletedAt}) {
    return CloudArtworkAssetRecord(
      id: 'artwork_1',
      userId: 'u1',
      storageObjectKey: 'u1/artwork_1.png',
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
      deletedAt: deletedAt,
    );
  }

  test('downloads, validates and returns an owned managed import', () async {
    final owned = await service().recover(record());

    expect(storage.requests.single, (
      userId: 'u1',
      artworkId: 'artwork_1',
      objectKey: 'u1/artwork_1.png',
      maxBytes: 4096,
    ));
    expect(validated, hasLength(1));
    expect(await File(owned.filePath).readAsBytes(), [1, 2, 3]);
    expect(downloads.listSync(), isEmpty);
  });

  test('an invalid image leaves no temporary or managed file', () async {
    validationError = StateError('not an image');

    await expectLater(service().recover(record()), throwsStateError);

    expect(downloads.listSync(), isEmpty);
    expect(managed.imports, isEmpty);
  });

  test('a failed download leaves nothing behind', () async {
    storage.error = const SocketException('connection reset');

    await expectLater(
      service().recover(record()),
      throwsA(isA<SocketException>()),
    );

    expect(downloads.listSync(), isEmpty);
    expect(validated, isEmpty);
    expect(managed.imports, isEmpty);
  });

  test('a failed managed import removes the temporary file', () async {
    managed.error = const FileSystemException('disk full');

    await expectLater(
      service().recover(record()),
      throwsA(isA<FileSystemException>()),
    );

    expect(downloads.listSync(), isEmpty);
  });

  test('a tombstoned row is never downloaded', () async {
    await expectLater(
      service().recover(record(deletedAt: DateTime.utc(2026, 10, 24))),
      throwsStateError,
    );

    expect(storage.requests, isEmpty);
  });
}

class _FakeStorage implements CloudArtworkStorage {
  final List<
    ({String userId, String artworkId, String objectKey, int maxBytes})
  >
  requests = [];
  Object? error;

  @override
  Future<String> downloadToTemporaryFile({
    required String userId,
    required String artworkId,
    required String objectKey,
    required String directoryPath,
    required int maxBytes,
  }) async {
    requests.add((
      userId: userId,
      artworkId: artworkId,
      objectKey: objectKey,
      maxBytes: maxBytes,
    ));

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    final file = File(p.join(directoryPath, 'download.png'));
    await file.create(exclusive: true);
    await file.writeAsBytes([1, 2, 3]);

    return file.path;
  }

  @override
  Future<String> upload({
    required String userId,
    required ArtworkAsset artworkAsset,
  }) => throw UnimplementedError();

  @override
  Future<String> uploadImmutable({
    required String userId,
    required ArtworkAsset artworkAsset,
    required String version,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteObject({
    required String userId,
    required String objectKey,
  }) => throw UnimplementedError();
}

class _FakeManagedStorage implements OwnedArtworkManagedStorage {
  _FakeManagedStorage(this.directory);

  final String directory;
  final List<String> imports = [];
  Object? error;

  @override
  Future<OwnedArtworkImport> importOwnedArtwork(String sourceFilePath) async {
    final failure = error;

    if (failure != null) {
      throw failure;
    }

    await Directory(directory).create(recursive: true);
    final target = p.join(directory, 'artwork_${imports.length}.png');
    await File(sourceFilePath).copy(target);
    imports.add(target);

    return _Owned(target);
  }
}

class _Owned implements OwnedArtworkImport {
  const _Owned(this.filePath);

  @override
  final String filePath;

  @override
  Future<void> discard() => File(filePath).delete();
}
