import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../../core/identity/text_normalizer.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_source_discovery_exception.dart';
import '../../domain/services/import_candidate_discovery.dart';

class FileSystemImportCandidateDiscovery implements ImportCandidateDiscovery {
  const FileSystemImportCandidateDiscovery();

  static const String supportedExtension = '.mp3';

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) async {
    final trimmedPath = filePath.trim();

    if (trimmedPath.isEmpty) {
      throw const ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.sourceMissing,
        message: 'Import file path cannot be empty.',
      );
    }

    final file = File(trimmedPath);

    if (!await file.exists()) {
      throw ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.sourceMissing,
        message: 'Import file does not exist.',
        path: trimmedPath,
      );
    }

    if (!_isSupportedAudioFile(file.path)) {
      throw ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.unsupportedFormat,
        message: 'Only MP3 files are supported for import.',
        path: trimmedPath,
      );
    }

    return _candidateFor(
      file.path,
      discoveredAt: discoveredAt ?? DateTime.now(),
    );
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async {
    final trimmedPath = rootPath.trim();

    if (trimmedPath.isEmpty) {
      throw const ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.sourceMissing,
        message: 'Import folder path cannot be empty.',
      );
    }

    final root = Directory(trimmedPath);

    if (!await root.exists()) {
      throw ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.sourceMissing,
        message: 'Import folder does not exist.',
        path: trimmedPath,
      );
    }

    final timestamp = discoveredAt ?? DateTime.now();
    final candidates = <ImportCandidate>[];

    final rootEntries = await root.list(followLinks: false).toList();

    for (final entry in rootEntries) {
      if (entry is! Directory) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Import root may contain only artist folders.',
          path: entry.path,
        );
      }
    }

    final artistDirectories = rootEntries.whereType<Directory>().toList()
      ..sort(_compareEntitiesByPath);

    for (final artistDirectory in artistDirectories) {
      final artistEntries = await artistDirectory
          .list(followLinks: false)
          .toList();

      if (artistEntries.isEmpty) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Artist folder must contain at least one album folder.',
          path: artistDirectory.path,
        );
      }

      for (final entry in artistEntries) {
        if (entry is! Directory) {
          throw ImportSourceDiscoveryException(
            type: ImportSourceDiscoveryFailureType.invalidStructure,
            message: 'Artist folders may contain only album folders.',
            path: entry.path,
          );
        }
      }

      final albumDirectories = artistEntries.whereType<Directory>().toList()
        ..sort(_compareEntitiesByPath);

      for (final albumDirectory in albumDirectories) {
        final albumEntries = await albumDirectory
            .list(followLinks: false)
            .toList();

        if (albumEntries.isEmpty) {
          throw ImportSourceDiscoveryException(
            type: ImportSourceDiscoveryFailureType.invalidStructure,
            message: 'Album folder must contain at least one MP3 file.',
            path: albumDirectory.path,
          );
        }

        for (final entry in albumEntries) {
          if (entry is! File) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.invalidStructure,
              message: 'Album folders may contain only MP3 files.',
              path: entry.path,
            );
          }

          if (!_isSupportedAudioFile(entry.path)) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.unsupportedFormat,
              message: 'Album folders may contain only MP3 files.',
              path: entry.path,
            );
          }
        }

        final audioFiles = albumEntries.whereType<File>().toList()
          ..sort(_compareEntitiesByPath);

        for (final audioFile in audioFiles) {
          candidates.add(
            _candidateFor(audioFile.path, discoveredAt: timestamp),
          );
        }
      }
    }

    return List.unmodifiable(candidates);
  }

  ImportCandidate _candidateFor(
    String filePath, {
    required DateTime discoveredAt,
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: TextNormalizer.normalizePath(filePath),
      discoveredAt: discoveredAt,
    );
  }

  bool _isSupportedAudioFile(String filePath) {
    return path.extension(filePath).toLowerCase() == supportedExtension;
  }

  int _compareEntitiesByPath(FileSystemEntity left, FileSystemEntity right) {
    return TextNormalizer.normalizePath(
      left.path,
    ).compareTo(TextNormalizer.normalizePath(right.path));
  }
}
