import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../../../core/database/database_tables.dart';
import '../models/backup_data_payload.dart';

class BackupArtworkItem {
  const BackupArtworkItem({
    required this.artworkId,
    required this.sourcePath,
    required this.archivePath,
    required this.byteLength,
    required this.sha256Digest,
  });

  final String artworkId;

  // Used only by the local export process. Never serialize this field.
  final String sourcePath;

  final String archivePath;
  final int byteLength;
  final String sha256Digest;

  Map<String, Object> toPortableJson() => {
    'artworkId': artworkId,
    'archivePath': archivePath,
    'byteLength': byteLength,
    'sha256': sha256Digest,
  };
}

class BackupArtworkInventoryService {
  const BackupArtworkInventoryService();

  Future<List<BackupArtworkItem>> build(BackupDataPayload payload) async {
    final rows = payload.tables[DatabaseTables.artworkAssets];

    if (rows == null) {
      throw const FormatException('Artwork table is missing.');
    }

    final results = <BackupArtworkItem>[];
    final seenIds = <String>{};
    final seenEntries = <String>{};

    for (final row in rows) {
      final id = row['id'];
      final sourcePath = row['file_path'];

      if (id is! String ||
          id.trim().isEmpty ||
          sourcePath is! String ||
          sourcePath.trim().isEmpty) {
        throw const FormatException(
          'Artwork record has an invalid identity or file path.',
        );
      }

      if (!seenIds.add(id)) {
        throw FormatException('Duplicate artwork ID: $id');
      }

      final sourceFile = File(sourcePath);

      if (await sourceFile.stat().then(
        (stat) => stat.type != FileSystemEntityType.file,
      )) {
        throw FormatException('Artwork file is missing: $id');
      }

      final extension = path.extension(sourcePath).toLowerCase();

      if (extension.isNotEmpty &&
          !RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)) {
        throw FormatException('Invalid artwork extension: $id');
      }

      // Hashing the ID gives the archive a portable, path-safe name.
      final archiveId = sha256.convert(utf8.encode(id)).toString();
      final archivePath = 'artwork/$archiveId$extension';

      if (!seenEntries.add(archivePath)) {
        throw FormatException('Duplicate artwork archive entry: $id');
      }

      final before = await sourceFile.length();

      if (before <= 0) {
        throw FormatException('Artwork file is empty: $id');
      }

      final digest = await sha256.bind(sourceFile.openRead()).first;
      final after = await sourceFile.length();

      if (before != after) {
        throw FormatException('Artwork changed during inventory: $id');
      }

      results.add(
        BackupArtworkItem(
          artworkId: id,
          sourcePath: sourcePath,
          archivePath: archivePath,
          byteLength: after,
          sha256Digest: digest.toString(),
        ),
      );
    }

    results.sort((a, b) => a.artworkId.compareTo(b.artworkId));

    return List.unmodifiable(results);
  }
}
