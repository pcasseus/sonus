import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/release_display_title.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  group('editionLabel (SN-50 BUG-03)', () {
    String label(String title, AlbumEditionType type) =>
        editionLabel(title: title, type: type, baseTitle: 'Skyline');

    test('an Other edition shows its own qualifier, never "Other"', () {
      expect(label('Skyline (Remixes)', AlbumEditionType.other), 'Remixes');
      expect(label('skyline [Live Cuts]', AlbumEditionType.other), 'Live Cuts');
      expect(label('Skyline - Demos', AlbumEditionType.other), 'Demos');
    });

    test('an Other name not built on the release title shows whole', () {
      expect(label('Night Remixes', AlbumEditionType.other), 'Night Remixes');
      expect(label('Skyline', AlbumEditionType.other), 'Skyline');
      expect(
        label('Skylines (B-Sides)', AlbumEditionType.other),
        'Skylines (B-Sides)',
      );
    });

    test('an unnamed Other edition still says Other', () {
      expect(label('', AlbumEditionType.other), 'Other');
      expect(label('Other', AlbumEditionType.other), 'Other');
    });

    test('typed editions keep their type label', () {
      expect(label('Skyline (Deluxe)', AlbumEditionType.deluxe), 'Deluxe');
      expect(label('Skyline', AlbumEditionType.standard), 'Standard');
      expect(label('Deluxe', AlbumEditionType.deluxe), 'Deluxe');
    });
  });

  test('editionTypeLabel names every type', () {
    expect(
      [for (final type in AlbumEditionType.values) editionTypeLabel(type)],
      ['Standard', 'Deluxe', 'Expanded', 'Anniversary', 'Remaster', 'Other'],
    );
  });

  test('releaseDisplayTitle shows an Other edition name over the base', () {
    expect(
      releaseDisplayTitle(
        baseTitle: 'Skyline',
        editionTitle: 'Skyline (Remixes)',
      ),
      'Skyline (Remixes)',
    );
    expect(
      releaseDisplayTitle(baseTitle: 'Skyline', editionTitle: 'Other'),
      'Skyline',
    );
  });
}
