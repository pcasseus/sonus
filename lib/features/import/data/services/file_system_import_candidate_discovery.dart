import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../../core/identity/text_normalizer.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/models/import_source_discovery_exception.dart';
import '../../domain/services/import_candidate_discovery.dart';

class FileSystemImportCandidateDiscovery implements ImportCandidateDiscovery {
  const FileSystemImportCandidateDiscovery();

  static const String supportedExtension = '.mp3';
  static const String lyricsExtension = '.lrc';

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
      lyricsPath: await _discoverLyricsSidecar(file),
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
              'containing album folders or an album folder containing MP3 '
              'files with optional LRC sidecars.',
          path: entry.path,
        );
      }

      if (files.isNotEmpty) {
        _validateAlbumFiles(files);

        final audioFiles = files.where(
          (file) => _isSupportedAudioFile(file.path),
        );

        for (final file in audioFiles) {
          candidates.add(
            _candidateFor(
              file.path,
              discoveredAt: timestamp,
              metadataFallbackPath: _relativePath(root: root, file: file),
              lyricsPath: _lyricsSidecarPath(file, files),
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
              message:
                  'Album folders may contain only MP3 files with optional '
                  'LRC sidecars.',
              path: albumEntry.path,
            );
          }
        }

        final albumFiles = albumEntries.whereType<File>().toList();
        _validateAlbumFiles(albumFiles);

        final audioFiles = albumFiles.where(
          (file) => _isSupportedAudioFile(file.path),
        );

        for (final audioFile in audioFiles) {
          candidates.add(
            _candidateFor(
              audioFile.path,
              discoveredAt: timestamp,
              metadataFallbackPath: _relativePath(root: root, file: audioFile),
              lyricsPath: _lyricsSidecarPath(audioFile, albumFiles),
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
    String? lyricsPath,
    required ImportCandidateStructure structure,
  }) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: TextNormalizer.normalizePath(filePath),
      discoveredAt: discoveredAt,
      metadataFallbackPath: metadataFallbackPath,
      lyricsPath: lyricsPath,
      structure: structure,
    );
  }

  void _validateAlbumFiles(List<File> files) {
    for (final file in files) {
      if (_isSupportedAudioFile(file.path) || _isLyricsFile(file.path)) {
        continue;
      }

      throw ImportSourceDiscoveryException(
        type: ImportSourceDiscoveryFailureType.unsupportedFormat,
        message:
            'Album folders may contain only MP3 files with optional '
            'LRC sidecars.',
        path: file.path,
      );
    }
  }

  Future<String?> _discoverLyricsSidecar(File audioFile) async {
    try {
      final siblings = await audioFile.parent
          .list(followLinks: false)
          .where((entry) => entry is File)
          .cast<File>()
          .toList();

      return _lyricsSidecarPath(audioFile, siblings);
    } catch (_) {
      return null;
    }
  }

  String? _lyricsSidecarPath(File audioFile, Iterable<File> files) {
    final audioStem = path
        .basenameWithoutExtension(audioFile.path)
        .toLowerCase();

    for (final file in files) {
      if (!_isLyricsFile(file.path)) {
        continue;
      }

      final lyricsStem = path.basenameWithoutExtension(file.path).toLowerCase();

      if (lyricsStem == audioStem) {
        return file.path;
      }
    }

    return null;
  }

  String _relativePath({required Directory root, required File file}) {
    return path.relative(file.path, from: root.path);
  }

  bool _isSupportedAudioFile(String filePath) {
    return path.extension(filePath).toLowerCase() == supportedExtension;
  }

  bool _isLyricsFile(String filePath) {
    return path.extension(filePath).toLowerCase() == lyricsExtension;
  }

  int _compareEntitiesByPath(FileSystemEntity left, FileSystemEntity right) {
    return TextNormalizer.normalizePath(
      left.path,
    ).compareTo(TextNormalizer.normalizePath(right.path));
  }
}
