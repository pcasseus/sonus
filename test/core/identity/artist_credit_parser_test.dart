import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/identity/artist_credit_parser.dart';

void main() {
  const parser = ArtistCreditParser();

  test('parses wrapped explicit feature credit', () {
    final result = parser.parseExplicitFeatureCredit(
      'Beyonc\u00E9 [Ft. Jack White]',
    );

    expect(result, isNotNull);
    expect(result!.primaryArtist, 'Beyonc\u00E9');
    expect(result.featuredArtist, 'Jack White');
  });

  test('parses direct explicit feature credit', () {
    final result = parser.parseExplicitFeatureCredit(
      'Beyonce featuring Jack White',
    );

    expect(result, isNotNull);
    expect(result!.primaryArtist, 'Beyonce');
    expect(result.featuredArtist, 'Jack White');
  });

  test('does not interpret arbitrary collaboration separator', () {
    expect(parser.parseExplicitFeatureCredit('Simon & Garfunkel'), isNull);
  });
}
