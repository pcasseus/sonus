import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';

class FakeMetadataReader implements AudioMetadataReader {
  FakeMetadataReader({this.result, this.error});

  final AudioMetadata? result;
  final Object? error;

  int callCount = 0;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    callCount++;

    if (error != null) {
      throw error!;
    }

    final resolved = result;

    if (resolved == null) {
      throw StateError('Fake reader has no result.');
    }

    return resolved;
  }
}

void main() {
  final candidate = ImportCandidate(
    filePath: r'C:\Music\Artist\Album\01 Song.mp3',
    normalizedPath: 'c:/music/artist/album/01 song.mp3',
    discoveredAt: DateTime.utc(2026, 9, 10),
  );

  final metadata = AudioMetadata(
    title: 'Song',
    artistName: 'Artist',
    albumTitle: 'Album',
    durationSeconds: 200,
    trackNumber: 1,
    discNumber: 1,
    isSingle: false,
    featuredArtists: const [],
  );

  test('returns metadata from primary reader when successful', () async {
    final primary = FakeMetadataReader(result: metadata);

    final fallback = FakeMetadataReader(
      result: metadata.copyWith(title: 'Fallback Song'),
    );

    final resolver = MetadataResolver(
      primaryReader: primary,
      fallbackReader: fallback,
    );

    final result = await resolver.resolve(candidate);

    expect(result.title, 'Song');
    expect(primary.callCount, 1);
    expect(fallback.callCount, 0);
  });

  test('uses fallback reader when primary reader fails', () async {
    final primary = FakeMetadataReader(
      error: const FormatException('Unreadable tags'),
    );

    final fallback = FakeMetadataReader(
      result: metadata.copyWith(title: 'Fallback Song'),
    );

    final resolver = MetadataResolver(
      primaryReader: primary,
      fallbackReader: fallback,
    );

    final result = await resolver.resolve(candidate);

    expect(result.title, 'Fallback Song');
    expect(primary.callCount, 1);
    expect(fallback.callCount, 1);
  });
}
