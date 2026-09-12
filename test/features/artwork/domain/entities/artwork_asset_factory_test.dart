import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset_factory.dart';

void main() {
  group('ArtworkAssetFactory', () {
    test('creates artwork asset from normalized trimmed path', () {
      final now = DateTime.utc(2026, 9, 12, 6, 30);

      final artwork = ArtworkAssetFactory.create(
        filePath: r'  C:\Music\Artwork\Cover.JPG  ',
        now: now,
      );

      expect(artwork.id, startsWith('artwork_'));
      expect(artwork.filePath, r'C:\Music\Artwork\Cover.JPG');
      expect(artwork.normalizedPath, 'c:/music/artwork/cover.jpg');
      expect(artwork.createdAt, now);
      expect(artwork.updatedAt, now);
    });

    test('rejects blank artwork path', () {
      expect(
        () => ArtworkAssetFactory.create(filePath: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
