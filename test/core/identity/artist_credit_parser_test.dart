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

  test('still reads every feature connector now that Sonus shows "Ft." '
      '(SN-50 BUG-05)', () {
    for (final credit in const [
      'Ada Vale feat. Ben Moor',
      'Ada Vale feat Ben Moor',
      'Ada Vale Ft. Ben Moor',
      'Ada Vale ft Ben Moor',
      'Ada Vale featuring Ben Moor',
      'Ada Vale (feat. Ben Moor)',
      'Ada Vale [ft. Ben Moor]',
    ]) {
      final result = parser.parseExplicitFeatureCredit(credit);

      expect(result?.primaryArtist, 'Ada Vale', reason: credit);
      expect(result?.featuredArtist, 'Ben Moor', reason: credit);
    }
  });

  test('does not interpret arbitrary collaboration separator', () {
    expect(parser.parseExplicitFeatureCredit('Simon & Garfunkel'), isNull);
  });

  group('splitNameList', () {
    test('splits unknown names at each comma and drops blanks', () {
      expect(parser.splitNameList(' Ada Vale, ,Ben Moor ,'), [
        'Ada Vale',
        'Ben Moor',
      ]);
    });

    test('keeps a known name containing a comma whole', () {
      expect(
        parser.splitNameList(
          'Crane, The Lantern, Ada Vale',
          knownNames: const ['Crane, The Lantern'],
        ),
        ['Crane, The Lantern', 'Ada Vale'],
      );
    });

    test('matches known names ignoring case and comma spacing', () {
      expect(
        parser.splitNameList(
          'Ada Vale, crane ,the lantern',
          knownNames: const ['Crane, The Lantern'],
        ),
        ['Ada Vale', 'crane, the lantern'],
      );
    });

    test('the longest known name wins', () {
      expect(
        parser.splitNameList(
          'Moth, Lamp, and Wick',
          knownNames: const ['Moth, Lamp', 'Moth, Lamp, and Wick'],
        ),
        ['Moth, Lamp, and Wick'],
      );
    });
  });
}
