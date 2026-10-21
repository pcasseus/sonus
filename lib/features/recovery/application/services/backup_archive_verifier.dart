import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../../../../core/database/database_tables.dart';
import '../models/backup_manifest.dart';
import 'backup_integrity_codec.dart';
import 'bounded_backup_output_stream.dart';
import 'backup_json_codec.dart';

class BackupArchiveVerifier {
  const BackupArchiveVerifier({
    this.integrityCodec = const BackupIntegrityCodec(),
  });

  final BackupIntegrityCodec integrityCodec;

  static const maxManifestBytes = 1024 * 1024;
  static const maxLibraryBytes = 64 * 1024 * 1024;
  static const maxArtworkBytes = 32 * 1024 * 1024;
  static const maxTotalBytes = 1024 * 1024 * 1024;
  static const maxEntries = 10000;

  Future<DecodedBackup> verify(File backupFile) async {
    if (!await backupFile.exists()) {
      throw const FormatException('Backup archive does not exist.');
    }

    final input = InputFileStream(backupFile.path);
    late final Archive archive;

    final seen = <String>{};
    final allowedPath = RegExp(r'^artwork/[0-9a-f]{64}(\.[a-z0-9]{1,10})?$');

    try {
      archive = ZipDecoder().decodeStream(
        input,
        callback: (entry) {
          if (!seen.add(entry.name)) {
            throw const FormatException('Duplicate backup archive entry.');
          }

          if (seen.length > maxEntries ||
              entry.isSymbolicLink ||
              (entry.mode & 0xf000) == 0xa000) {
            throw const FormatException('Unsafe backup archive entry.');
          }

          if (entry.isDirectory) {
            if (entry.name != 'artwork/') {
              throw const FormatException('Unexpected backup directory.');
            }
            return;
          }

          final limit = switch (entry.name) {
            'manifest.json' => maxManifestBytes,
            'library.json' => maxLibraryBytes,
            _ => maxArtworkBytes,
          };

          if (entry.name != 'manifest.json' &&
              entry.name != 'library.json' &&
              !allowedPath.hasMatch(entry.name)) {
            throw const FormatException('Unexpected backup archive path.');
          }

          if (entry.size < 0 || entry.size > limit) {
            throw const FormatException('Backup entry exceeds size limit.');
          }
        },
      );

      var totalSize = 0;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        totalSize += entry.size;

        if (totalSize > maxTotalBytes) {
          throw const FormatException('Backup exceeds size limit.');
        }
      }

      final entries = {
        for (final entry in archive.files)
          if (entry.isFile) entry.name: entry,
      };

      final manifestFile = entries['manifest.json'];
      final libraryFile = entries['library.json'];

      if (manifestFile == null || libraryFile == null) {
        throw const FormatException('Required backup entries are missing.');
      }

      final manifestOutput = BoundedBackupOutputStream(
        maxBytes: maxManifestBytes,
      );
      manifestFile.writeContent(manifestOutput);
      final manifestBytes = manifestOutput.getBytes();

      final libraryOutput = BoundedBackupOutputStream(
        maxBytes: maxLibraryBytes,
      );
      libraryFile.writeContent(libraryOutput);
      final libraryBytes = libraryOutput.getBytes();

      if (manifestBytes.isEmpty || libraryBytes.isEmpty) {
        throw const FormatException('Invalid backup document bytes.');
      }

      final Object? manifestDocument;
      try {
        manifestDocument = jsonDecode(utf8.decode(manifestBytes));
      } on FormatException {
        throw const FormatException('Invalid archive manifest JSON.');
      }

      if (manifestDocument is! Map<String, dynamic> ||
          manifestDocument.length != 2 ||
          manifestDocument['manifest'] is! Map<String, dynamic> ||
          manifestDocument['artwork'] is! List) {
        throw const FormatException('Invalid archive manifest structure.');
      }

      final manifest = BackupManifest.fromJson(
        manifestDocument['manifest'] as Map<String, dynamic>,
      );

      final backup = integrityCodec.decode(utf8.decode(libraryBytes));
      final actualManifest = backup.manifest;

      if (manifest.backupId != actualManifest.backupId ||
          manifest.databaseVersion != actualManifest.databaseVersion ||
          manifest.formatVersion != actualManifest.formatVersion ||
          manifest.createdAtUtc != actualManifest.createdAtUtc ||
          manifest.rowCounts.length != actualManifest.rowCounts.length ||
          manifest.rowCounts.keys.any(
            (key) => manifest.rowCounts[key] != actualManifest.rowCounts[key],
          )) {
        throw const FormatException('Backup manifests disagree.');
      }

      final artwork = manifestDocument['artwork'] as List;
      final expectedArtworkPaths = <String>{};
      final expectedArtworkIds = <String>{};

      for (final item in artwork) {
        if (item is! Map<String, dynamic> ||
            item.length != 4 ||
            item['artworkId'] is! String ||
            item['archivePath'] is! String ||
            item['byteLength'] is! int ||
            item['sha256'] is! String) {
          throw const FormatException('Invalid artwork inventory entry.');
        }

        final id = item['artworkId'] as String;
        final name = item['archivePath'] as String;
        final length = item['byteLength'] as int;
        final digest = item['sha256'] as String;

        if (id.isEmpty ||
            !expectedArtworkIds.add(id) ||
            !allowedPath.hasMatch(name) ||
            !name.startsWith('artwork/${sha256.convert(utf8.encode(id))}') ||
            !expectedArtworkPaths.add(name) ||
            length <= 0 ||
            length > maxArtworkBytes ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
          throw const FormatException('Invalid artwork inventory metadata.');
        }

        final entry = entries[name];
        if (entry == null || entry.size != length) {
          throw const FormatException('Missing or incorrect artwork file.');
        }

        final output = BoundedBackupOutputStream(maxBytes: length);
        entry.writeContent(output);

        final bytes = output.getBytes();

        if (bytes.length != length ||
            sha256.convert(bytes).toString() != digest) {
          throw const FormatException('Artwork integrity check failed.');
        }
      }

      final actualArtworkPaths = entries.keys
          .where((name) => name.startsWith('artwork/'))
          .toSet();

      if (actualArtworkPaths.length != expectedArtworkPaths.length ||
          !actualArtworkPaths.containsAll(expectedArtworkPaths)) {
        throw const FormatException('Unlisted artwork in backup.');
      }

      final databaseArtworkRows =
          backup.payload.tables[DatabaseTables.artworkAssets];

      if (databaseArtworkRows == null) {
        throw const FormatException('Backup artwork table is missing.');
      }

      final databaseArtworkIds = <String>{};

      for (final row in databaseArtworkRows) {
        final id = row['id'];

        if (id is! String || id.trim().isEmpty || !databaseArtworkIds.add(id)) {
          throw const FormatException(
            'Invalid or duplicate database artwork identity.',
          );
        }
      }

      if (databaseArtworkIds.length != expectedArtworkIds.length ||
          !databaseArtworkIds.containsAll(expectedArtworkIds)) {
        throw const FormatException(
          'Artwork inventory does not match database records.',
        );
      }
      return backup;
    } finally {
      await input.close();
    }
  }
}
