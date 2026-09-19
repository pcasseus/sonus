import 'package:path/path.dart' as path;
import 'package:saf/saf.dart';

import '../../../../core/identity/text_normalizer.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_source_discovery_exception.dart';
import '../../domain/services/import_candidate_discovery.dart';
import 'file_system_import_candidate_discovery.dart';

typedef SafWalk = Stream<SafWalkEntry> Function(String directoryUri);

class SafImportCandidateDiscovery implements ImportCandidateDiscovery {
  SafImportCandidateDiscovery({
    required Saf saf,
    FileSystemImportCandidateDiscovery? fileSystemDiscovery,
  }) : _walk = saf.walk,
       _fileSystemDiscovery =
           fileSystemDiscovery ?? const FileSystemImportCandidateDiscovery();

  SafImportCandidateDiscovery.forTesting({
    required SafWalk walk,
    FileSystemImportCandidateDiscovery? fileSystemDiscovery,
  }) : this._(
         walk,
         fileSystemDiscovery ?? const FileSystemImportCandidateDiscovery(),
       );

  SafImportCandidateDiscovery._(this._walk, this._fileSystemDiscovery);
  static const String supportedExtension = '.mp3';

  final SafWalk _walk;
  final FileSystemImportCandidateDiscovery _fileSystemDiscovery;

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) {
    return _fileSystemDiscovery.discoverFile(
      filePath,
      discoveredAt: discoveredAt,
    );
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async {
    final trimmedRoot = rootPath.trim();

    if (trimmedRoot.isEmpty) {
      throw const ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.sourceMissing,
        message: 'Import folder path cannot be empty.',
      );
    }

    if (!trimmedRoot.startsWith('content://')) {
      return _fileSystemDiscovery.discoverFolder(
        trimmedRoot,
        discoveredAt: discoveredAt,
      );
    }

    final timestamp = discoveredAt ?? DateTime.now();
    final entries = await _walk(trimmedRoot).toList();

    final topLevelFiles = <String>{};
    final topLevelDirectories = <String>{};
    final candidates = <ImportCandidate>[];

    for (final entry in entries) {
      final relativePath = entry.relativePath
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^/+|/+$'), '');

      if (relativePath.isEmpty) {
        continue;
      }

      final segments = relativePath
          .split('/')
          .where((segment) => segment.trim().isNotEmpty)
          .toList(growable: false);

      if (entry.file.isDir) {
        if (segments.length == 1) {
          continue;
        }

        if (segments.length == 2) {
          topLevelDirectories.add(segments[0]);
          continue;
        }

        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Album folders may not contain additional folders.',
          path: relativePath,
        );
      }

      if (segments.length == 1) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Import root may contain only artist or album folders.',
          path: relativePath,
        );
      }

      if (segments.length != 2 && segments.length != 3) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Album folders may contain only MP3 files.',
          path: relativePath,
        );
      }

      if (path.extension(entry.file.name).toLowerCase() != supportedExtension) {
        throw ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.unsupportedFormat,
          message: 'Album folders may contain only MP3 files.',
          path: relativePath,
        );
      }

      final structure = segments.length == 2
          ? ImportCandidateStructure.looseAlbum
          : ImportCandidateStructure.artistAlbum;

      if (structure == ImportCandidateStructure.looseAlbum) {
        topLevelFiles.add(segments[0]);
      } else {
        topLevelDirectories.add(segments[0]);
      }

      candidates.add(
        ImportCandidate(
          filePath: entry.file.uri,
          normalizedPath: TextNormalizer.normalizePath(entry.file.uri),
          discoveredAt: timestamp,
          metadataFallbackPath: entry.relativePath,
          structure: structure,
        ),
      );
    }

    final mixedTopLevelFolders = topLevelFiles.intersection(
      topLevelDirectories,
    );

    if (mixedTopLevelFolders.isNotEmpty) {
      final folder = mixedTopLevelFolders.toList()..sort();

      throw ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.invalidStructure,
        message:
            'A top-level folder must be either an artist folder '
            'containing album folders or an album folder containing MP3 files.',
        path: folder.first,
      );
    }

    candidates.sort(
      (left, right) =>
          TextNormalizer.normalizePath(
            left.metadataFallbackPath ?? left.filePath,
          ).compareTo(
            TextNormalizer.normalizePath(
              right.metadataFallbackPath ?? right.filePath,
            ),
          ),
    );

    return List.unmodifiable(candidates);
  }
}
