import 'package:path/path.dart' as path;

import '../../domain/models/audio_metadata.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/services/audio_metadata_reader.dart';

class PathFallbackMetadataReader implements AudioMetadataReader {
  const PathFallbackMetadataReader();

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final fallbackPath =
        candidate.metadataFallbackPath?.trim() ??
        candidate.normalizedPath.trim();

    if (fallbackPath.isEmpty || fallbackPath.startsWith('content://')) {
      throw const FormatException('Cannot derive metadata from this source.');
    }

    final parts = path
        .split(fallbackPath)
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      throw const FormatException('Cannot derive metadata from path.');
    }

    final fileName = parts.last;
    final title = _titleFromFileName(fileName);

    final artistName = switch (parts.length) {
      >= 3 => _cleanSegment(parts[parts.length - 3]),
      2 => 'Unknown Artist',
      _ => 'Unknown Artist',
    };

    final albumTitle = switch (parts.length) {
      >= 3 => _cleanSegment(parts[parts.length - 2]),
      2 => _cleanSegment(parts[0]),
      _ => 'Unknown Album',
    };

    return AudioMetadata(
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      albumArtistName: artistName,
      durationSeconds: 0,
      trackNumber: _trackNumberFromFileName(fileName),
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  String _titleFromFileName(String fileName) {
    final withoutExtension = path.basenameWithoutExtension(fileName);

    final withoutTrackPrefix = withoutExtension.replaceFirst(
      RegExp(r'^\s*\d+\s*[-._ ]+\s*'),
      '',
    );

    final cleaned = _cleanSegment(withoutTrackPrefix);

    if (cleaned.isEmpty) {
      return 'Unknown Song';
    }

    return cleaned;
  }

  int _trackNumberFromFileName(String fileName) {
    final withoutExtension = path.basenameWithoutExtension(fileName);

    final match = RegExp(r'^\s*(\d+)').firstMatch(withoutExtension);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _cleanSegment(String value) {
    return value.trim().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
  }
}
