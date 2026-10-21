import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../../../core/database/database_tables.dart';
import '../models/backup_data_payload.dart';
import '../models/backup_failure.dart';

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
    final sources = <String, String>{};
    final missingIds = <String>[];

    for (final row in rows) {
      final id = row['id'];
      final sourcePath = row['file_path'];

      if (id is! String ||
          id.trim().isEmpty ||
          sourcePath is! String ||
          sourcePath.trim().isEmpty) {
        throw BackupException(
          BackupFailureCode.invalidArtwork,
          'Artwork record has an invalid identity or file path.',
        );
      }

      if (!seenIds.add(id)) {
        throw BackupException(
          BackupFailureCode.invalidArtwork,
          'Duplicate artwork ID: $id',
          artworkIds: [id],
        );
      }

      if (await File(sourcePath).stat().then(
        (stat) => stat.type != FileSystemEntityType.file,
      )) {
        missingIds.add(id);
      }

      sources[id] = sourcePath;
    }

    // Report every missing file at once so the user can repair them together.
    if (missingIds.isNotEmpty) {
      missingIds.sort();

      throw BackupException(
        BackupFailureCode.missingArtwork,
        missingIds.length == 1
            ? 'Artwork file is missing: ${missingIds.single}'
            : '${missingIds.length} artwork files are missing.',
        artworkIds: missingIds,
      );
    }

    for (final MapEntry(key: id, value: sourcePath) in sources.entries) {
      final sourceFile = File(sourcePath);
      final extension = path.extension(sourcePath).toLowerCase();

      if (extension.isNotEmpty &&
          !RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)) {
        throw BackupException(
          BackupFailureCode.invalidArtwork,
          'Invalid artwork extension: $id',
          artworkIds: [id],
        );
      }

      // Hashing the ID gives the archive a portable, path-safe name.
      final archiveId = sha256.convert(utf8.encode(id)).toString();
      final archivePath = 'artwork/$archiveId$extension';

      if (!seenEntries.add(archivePath)) {
        throw BackupException(
          BackupFailureCode.invalidArtwork,
          'Duplicate artwork archive entry: $id',
          artworkIds: [id],
        );
      }

      final before = await sourceFile.length();

      if (before <= 0) {
        throw BackupException(
          BackupFailureCode.invalidArtwork,
          'Artwork file is empty: $id',
          artworkIds: [id],
        );
      }

      final digest = await sha256.bind(sourceFile.openRead()).first;
      final after = await sourceFile.length();

      if (before != after) {
        throw BackupException(
          BackupFailureCode.artworkChanged,
          'Artwork changed during inventory: $id',
          artworkIds: [id],
        );
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
