import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/recovery/application/models/backup_data_payload.dart';
import 'package:sonus_next/features/recovery/application/models/backup_table_coverage.dart';
import 'package:sonus_next/features/recovery/application/services/backup_artwork_inventory_service.dart';

BackupDataPayload payloadWithArtwork(List<Map<String, Object?>> artwork) {
  return BackupDataPayload(
    tables: {
      for (final entry in BackupCoverageContract.portableTables)
        entry.table: entry.table == DatabaseTables.artworkAssets
            ? artwork
            : <Map<String, Object?>>[],
    },
  );
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sonus_backup_artwork_');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  const service = BackupArtworkInventoryService();

  test('accepts a backup with no artwork', () async {
    final inventory = await service.build(payloadWithArtwork([]));
    expect(inventory, isEmpty);
  });

  test('preserves artwork identity and hashes real bytes', () async {
    final file = File('${directory.path}/cover.jpg');
    final bytes = <int>[1, 2, 3, 4, 5];

    await file.writeAsBytes(bytes);

    final inventory = await service.build(
      payloadWithArtwork([
        {'id': 'artwork-1', 'file_path': file.path},
      ]),
    );

    expect(inventory, hasLength(1));

    final item = inventory.single;

    expect(item.artworkId, 'artwork-1');
    expect(item.sourcePath, file.path);
    expect(item.byteLength, bytes.length);
    expect(item.sha256Digest, sha256.convert(bytes).toString());
    expect(item.archivePath, startsWith('artwork/'));
    expect(item.archivePath, endsWith('.jpg'));

    final portable = item.toPortableJson();

    expect(portable['artworkId'], 'artwork-1');
    expect(portable['byteLength'], 5);
    expect(portable['sha256'], item.sha256Digest);
    expect(portable.containsKey('sourcePath'), isFalse);
    expect(portable.containsKey('file_path'), isFalse);
  });

  test('rejects missing artwork files', () async {
    final payload = payloadWithArtwork([
      {'id': 'missing-artwork', 'file_path': '${directory.path}/missing.jpg'},
    ]);

    await expectLater(service.build(payload), throwsFormatException);
  });

  test('rejects empty artwork files', () async {
    final file = File('${directory.path}/empty.png');
    await file.create();

    await expectLater(
      service.build(
        payloadWithArtwork([
          {'id': 'empty-artwork', 'file_path': file.path},
        ]),
      ),
      throwsFormatException,
    );
  });

  test('rejects duplicate artwork identities', () async {
    final file = File('${directory.path}/cover.jpg');
    await file.writeAsBytes([1, 2, 3]);

    await expectLater(
      service.build(
        payloadWithArtwork([
          {'id': 'same-id', 'file_path': file.path},
          {'id': 'same-id', 'file_path': file.path},
        ]),
      ),
      throwsFormatException,
    );
  });

  test('rejects blank artwork identities', () async {
    final file = File('${directory.path}/cover.jpg');
    await file.writeAsBytes([1]);

    await expectLater(
      service.build(
        payloadWithArtwork([
          {'id': ' ', 'file_path': file.path},
        ]),
      ),
      throwsFormatException,
    );
  });
}
