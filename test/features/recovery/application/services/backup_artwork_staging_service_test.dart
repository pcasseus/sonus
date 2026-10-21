import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sonus_next/features/recovery/application/services/backup_artwork_inventory_service.dart';
import 'package:sonus_next/features/recovery/application/services/backup_artwork_staging_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_stage_test_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  const service = BackupArtworkStagingService();

  Future<BackupArtworkItem> makeItem({
    required String id,
    required List<int> bytes,
  }) async {
    final source = File(path.join(root.path, '$id.jpg'));
    await source.writeAsBytes(bytes);

    final digest = sha256.convert(bytes).toString();

    return BackupArtworkItem(
      artworkId: id,
      sourcePath: source.path,
      archivePath: 'artwork/${sha256.convert(id.codeUnits)}.jpg',
      byteLength: bytes.length,
      sha256Digest: digest,
    );
  }

  test('copies artwork and preserves exact bytes', () async {
    final bytes = <int>[10, 20, 30, 40];
    final item = await makeItem(id: 'cover-1', bytes: bytes);
    final staging = Directory(path.join(root.path, 'staging'));

    await service.stage(inventory: [item], stagingDirectory: staging);

    final stagedFile = File(
      path.joinAll([staging.path, ...item.archivePath.split('/')]),
    );

    expect(await stagedFile.readAsBytes(), bytes);
  });

  test('rejects source changes and cleans incomplete staging', () async {
    final item = await makeItem(id: 'cover-2', bytes: [1, 2, 3]);

    await File(item.sourcePath).writeAsBytes([9, 8, 7]);

    final staging = Directory(path.join(root.path, 'staging'));

    await expectLater(
      service.stage(inventory: [item], stagingDirectory: staging),
      throwsFormatException,
    );

    expect(await staging.exists(), isFalse);
  });

  test('cleans previously copied artwork when a later file fails', () async {
    final first = await makeItem(id: 'first-cover', bytes: [1, 2, 3]);
    final second = await makeItem(id: 'second-cover', bytes: [4, 5, 6]);

    // Invalidate the second file after its inventory was recorded.
    await File(second.sourcePath).writeAsBytes([7, 8, 9]);

    final staging = Directory(path.join(root.path, 'staging'));

    await expectLater(
      service.stage(inventory: [first, second], stagingDirectory: staging),
      throwsFormatException,
    );

    expect(await staging.exists(), isFalse);
    expect(await File(first.sourcePath).readAsBytes(), [1, 2, 3]);
    expect(await File(second.sourcePath).readAsBytes(), [7, 8, 9]);
  });
  test('rejects invalid archive paths', () async {
    final item = await makeItem(id: 'cover-3', bytes: [1]);
    final staging = Directory(path.join(root.path, 'staging'));

    final invalid = BackupArtworkItem(
      artworkId: item.artworkId,
      sourcePath: item.sourcePath,
      archivePath: '../escape.jpg',
      byteLength: item.byteLength,
      sha256Digest: item.sha256Digest,
    );

    await expectLater(
      service.stage(inventory: [invalid], stagingDirectory: staging),
      throwsFormatException,
    );

    expect(await staging.exists(), isFalse);
  });

  test('rejects staging into an existing directory', () async {
    final staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    await expectLater(
      service.stage(inventory: [], stagingDirectory: staging),
      throwsStateError,
    );
  });

  test('accepts an empty inventory', () async {
    final staging = Directory(path.join(root.path, 'staging'));

    await service.stage(inventory: [], stagingDirectory: staging);

    expect(await staging.exists(), isTrue);
    expect(await staging.list().isEmpty, isTrue);
  });
}
