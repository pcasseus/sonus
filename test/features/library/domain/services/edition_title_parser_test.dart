import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/services/edition_title_parser.dart';

void main() {
  (String, AlbumEditionType)? parse(String title) {
    final parsed = EditionTitleParser.parse(title);
    return parsed == null ? null : (parsed.baseTitle, parsed.type);
  }

  test('recognizes common edition qualifiers', () {
    expect(parse('locket (Deluxe)'), ('locket', AlbumEditionType.deluxe));
    expect(parse('Album [Deluxe Edition]'), ('Album', AlbumEditionType.deluxe));
    expect(parse('Album (Super Deluxe)'), ('Album', AlbumEditionType.deluxe));
    expect(parse('Album - Deluxe Version'), ('Album', AlbumEditionType.deluxe));
    expect(parse('Album (Expanded Edition)'), (
      'Album',
      AlbumEditionType.expanded,
    ));
    expect(parse('Album (10th Anniversary Edition)'), (
      'Album',
      AlbumEditionType.anniversary,
    ));
    expect(parse('Album (2011 Remaster)'), (
      'Album',
      AlbumEditionType.remaster,
    ));
    expect(parse('Album (Remastered)'), ('Album', AlbumEditionType.remaster));
    expect(parse('Album (Platinum Edition)'), (
      'Album',
      AlbumEditionType.other,
    ));
  });

  test('ordinary bracketed words are part of the title', () {
    expect(parse("it's not that deep (unless you want it to be)"), isNull);
    expect(parse('Songs (For You)'), isNull);
    expect(parse('Live (2019)'), isNull);
    expect(parse('Deluxe'), isNull);
    expect(parse('(Deluxe)'), isNull);
    expect(parse('locket'), isNull);
    expect(parse('A Night At The Deluxe'), isNull);
  });
}
