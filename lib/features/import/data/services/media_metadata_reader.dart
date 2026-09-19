import 'dart:io';

import 'package:media_metadata/media_metadata.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

import '../../domain/models/audio_metadata.dart';
import '../../domain/models/import_candidate.dart';
import '../../domain/services/audio_metadata_reader.dart';

class MediaMetadataReader implements AudioMetadataReader {
  const MediaMetadataReader({this.saf});

  final Saf? saf;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final source = candidate.filePath.trim();

    if (!source.startsWith('content://')) {
      return _readPath(source);
    }

    final safInstance = saf;

    if (safInstance == null) {
      throw StateError('SAF access is required to read content URI metadata.');
    }

    final cacheRoot = await getTemporaryDirectory();
    final metadataCacheDirectory = await Directory(
      path.join(cacheRoot.path, 'sonus_import_metadata'),
    ).create(recursive: true);

    final workingDirectory = await metadataCacheDirectory.createTemp(
      'candidate_',
    );

    final temporaryFile = File(path.join(workingDirectory.path, 'source.mp3'));

    try {
      await safInstance.copyToLocalFile(source, temporaryFile.path);

      return await _readPath(temporaryFile.path);
    } finally {
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
    }
  }

  Future<AudioMetadata> _readPath(String filePath) async {
    final metadata = await MediaMetadata.read(filePath);

    if (metadata == null) {
      throw const FormatException(
        'Audio file does not contain readable metadata.',
      );
    }

    final year = metadata.year;

    return AudioMetadata(
      title: metadata.title?.trim() ?? '',
      artistName: metadata.artist?.trim() ?? '',
      albumTitle: metadata.album?.trim() ?? '',
      albumArtistName: _cleanOptional(metadata.albumArtist),
      durationSeconds: metadata.duration?.inSeconds ?? 0,
      trackNumber: metadata.trackNumber ?? 0,
      discNumber: metadata.discNumber ?? 1,
      isSingle: false,
      featuredArtists: const [],
      releaseDate: year == null || year <= 0 ? null : DateTime(year),
      genre: _cleanOptional(metadata.genre),
    );
  }

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }
}
