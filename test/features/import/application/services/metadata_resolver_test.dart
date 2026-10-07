import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/resolved_metadata.dart';
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

    expect(result.metadata.title, 'Song');
    expect(result.source, MetadataSource.embedded);
    expect(result.origins, isNotNull);
    expect(result.origins!.title, ImportMetadataFieldSource.embedded);
    expect(result.origins!.artistName, ImportMetadataFieldSource.embedded);
    expect(result.origins!.albumTitle, ImportMetadataFieldSource.embedded);
    expect(result.usedFallback, isFalse);
    expect(primary.callCount, 1);
    expect(fallback.callCount, 0);
  });

  test('mixed metadata is treated as having used fallback data', () {
    final result = ResolvedMetadata(
      metadata: metadata,
      source: MetadataSource.mixed,
    );

    expect(result.usedFallback, isTrue);
    expect(result.origins, isNull);
  });

  test(
    'merges fallback identity with valid embedded technical metadata',
    () async {
      final primary = FakeMetadataReader(
        result: AudioMetadata(
          title: '',
          artistName: '',
          albumTitle: '',
          durationSeconds: 74,
          trackNumber: 0,
          discNumber: 1,
          isSingle: false,
          featuredArtists: const [],
          genre: 'Pop',
        ),
      );

      final fallback = FakeMetadataReader(
        result: AudioMetadata(
          title: 'Testing 5',
          artistName: 'Test Artist',
          albumTitle: 'Test Album',
          albumArtistName: 'Test Artist',
          durationSeconds: 0,
          trackNumber: 5,
          discNumber: 1,
          isSingle: false,
          featuredArtists: const [],
        ),
      );

      final resolver = MetadataResolver(
        primaryReader: primary,
        fallbackReader: fallback,
      );

      final result = await resolver.resolve(candidate);

      expect(result.source, MetadataSource.mixed);
      expect(result.origins, isNotNull);
      final origins = result.origins!;

      expect(origins.title, ImportMetadataFieldSource.fallback);
      expect(origins.artistName, ImportMetadataFieldSource.fallback);
      expect(origins.albumTitle, ImportMetadataFieldSource.fallback);
      expect(origins.albumArtistName, ImportMetadataFieldSource.fallback);
      expect(origins.trackNumber, ImportMetadataFieldSource.fallback);
      expect(origins.discNumber, ImportMetadataFieldSource.embedded);
      expect(origins.isSingle, ImportMetadataFieldSource.embedded);
      expect(origins.featuredArtists, ImportMetadataFieldSource.embedded);
      expect(origins.releaseDate, ImportMetadataFieldSource.fallback);
      expect(origins.genre, ImportMetadataFieldSource.embedded);
      expect(result.usedFallback, isTrue);
      expect(result.metadata.title, 'Testing 5');
      expect(result.metadata.artistName, 'Test Artist');
      expect(result.metadata.albumTitle, 'Test Album');
      expect(result.metadata.albumArtistName, 'Test Artist');

      // The important SN-24 regression:
      // fallback identity must not destroy a valid embedded runtime.
      expect(result.metadata.durationSeconds, 74);

      expect(result.metadata.trackNumber, 5);
      expect(result.metadata.discNumber, 1);
      expect(result.metadata.genre, 'Pop');
      expect(primary.callCount, 1);
      expect(fallback.callCount, 1);
    },
  );

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

    expect(result.metadata.title, 'Fallback Song');
    expect(result.source, MetadataSource.fallback);
    expect(result.origins, isNotNull);
    final fallbackOrigins = result.origins!;
    expect(fallbackOrigins.title, ImportMetadataFieldSource.fallback);
    expect(fallbackOrigins.artistName, ImportMetadataFieldSource.fallback);
    expect(fallbackOrigins.albumTitle, ImportMetadataFieldSource.fallback);
    expect(result.usedFallback, isTrue);
    expect(primary.callCount, 1);
    expect(fallback.callCount, 1);
  });

  test(
    'does not retry fallback when fallback fails after a successful primary read',
    () async {
      final primary = FakeMetadataReader(result: metadata.copyWith(title: ''));

      final fallback = FakeMetadataReader(
        error: const FormatException('Fallback failed'),
      );

      final resolver = MetadataResolver(
        primaryReader: primary,
        fallbackReader: fallback,
      );

      await expectLater(
        resolver.resolve(candidate),
        throwsA(isA<FormatException>()),
      );

      expect(primary.callCount, 1);
      expect(fallback.callCount, 1);
    },
  );
}
