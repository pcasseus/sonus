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
      structure: ImportCandidateStructure.singleFile,
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

    final rootEntries = await root.list(followLinks: false).toList()
      ..sort(_compareEntitiesByPath);

    for (final entry in rootEntries) {
      if (entry is! Directory) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Import root may contain only artist or album folders.',
          path: entry.path,
        );
      }

      final topLevelEntries = await entry.list(followLinks: false).toList()
        ..sort(_compareEntitiesByPath);

      if (topLevelEntries.isEmpty) {
        continue;
      }

      final files = topLevelEntries.whereType<File>().toList();
      final directories = topLevelEntries.whereType<Directory>().toList();

      if (files.isNotEmpty && directories.isNotEmpty) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message:
              'A top-level folder must be either an artist folder '
              'containing album folders or an album folder containing MP3 files.',
          path: entry.path,
        );
      }

      if (files.isNotEmpty) {
        for (final file in files) {
          if (!_isSupportedAudioFile(file.path)) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.unsupportedFormat,
              message: 'Album folders may contain only MP3 files.',
              path: file.path,
            );
          }

          candidates.add(
            _candidateFor(
              file.path,
              discoveredAt: timestamp,
              metadataFallbackPath: _relativePath(root: root, file: file),
              structure: ImportCandidateStructure.looseAlbum,
            ),
          );
        }

        continue;
      }

      for (final albumDirectory in directories) {
        final albumEntries =
            await albumDirectory.list(followLinks: false).toList()
              ..sort(_compareEntitiesByPath);

        if (albumEntries.isEmpty) {
          continue;
        }

        for (final albumEntry in albumEntries) {
          if (albumEntry is Directory) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.invalidStructure,
              message: 'Album folders may not contain additional folders.',
              path: albumEntry.path,
            );
          }

          if (albumEntry is! File) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.invalidStructure,
              message: 'Album folders may contain only MP3 files.',
              path: albumEntry.path,
            );
          }

          if (!_isSupportedAudioFile(albumEntry.path)) {
            throw ImportSourceDiscoveryException(
              type: ImportSourceDiscoveryFailureType.unsupportedFormat,
              message: 'Album folders may contain only MP3 files.',
              path: albumEntry.path,
            );
          }

          candidates.add(
            _candidateFor(
              albumEntry.path,
              discoveredAt: timestamp,
              metadataFallbackPath: _relativePath(root: root, file: albumEntry),
              structure: ImportCandidateStructure.artistAlbum,
            ),
          );
        }
      }
    }

    return List.unmodifiable(candidates);
  }

  ImportCandidate _candidateFor(
    String filePath, {
    required DateTime discoveredAt,
    String? metadataFallbackPath,
    required ImportCandidateStructure structure,
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: TextNormalizer.normalizePath(filePath),
      discoveredAt: discoveredAt,
      metadataFallbackPath: metadataFallbackPath,
      structure: structure,
    );
  }

  String _relativePath({required Directory root, required File file}) {
    return path.relative(file.path, from: root.path);
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
