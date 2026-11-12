// App Update 1.2, REF-14: canonical genres, exact aliases only.
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/services/genre_catalog.dart';

void main() {
  test('the suggested categories', () {
    expect(GenreCatalog.categories, [
      'Pop',
      'Hip-Hop/Rap',
      'R&B/Soul',
      'Rock',
      'Alternative',
      'Dance/Electronic',
      'Country',
      'Latin',
      'Jazz',
      'Classical',
      'Reggae/Dancehall',
      'Afrobeats',
      'Gospel',
      'Folk',
      'Metal',
      'Soundtrack',
      'Other',
    ]);
  });

  test('common spellings and capitalization map to their category', () {
    for (final (written, category) in [
      ('hip hop', 'Hip-Hop/Rap'),
      ('Hip-Hop', 'Hip-Hop/Rap'),
      ('RAP', 'Hip-Hop/Rap'),
      ('hip-hop/rap', 'Hip-Hop/Rap'),
      ('Hip Hop & Rap', 'Hip-Hop/Rap'),
      ('r&b', 'R&B/Soul'),
      ('RnB', 'R&B/Soul'),
      ('R & B', 'R&B/Soul'),
      ('Rhythm and Blues', 'R&B/Soul'),
      ('soul', 'R&B/Soul'),
      ('EDM', 'Dance/Electronic'),
      ('Electronic', 'Dance/Electronic'),
      ('alternative rock', 'Alternative'),
      ('Dancehall', 'Reggae/Dancehall'),
      ('Afrobeat', 'Afrobeats'),
      ('Original Soundtrack', 'Soundtrack'),
      ('  pop  ', 'Pop'),
    ]) {
      expect(GenreCatalog.canonicalOf(written), category, reason: written);
    }
  });

  test('anything that is not an exact alias is shown as written, never '
      'guessed', () {
    for (final written in [
      'Pop Rock',
      'Indie Folk',
      'K-Pop',
      'Trap Soul',
      'Neo Soul',
      'Hyperpop',
      'Score',
    ]) {
      expect(GenreCatalog.canonicalOf(written), isNull, reason: written);
      expect(GenreCatalog.display(written), written.trim(), reason: written);
    }
    expect(GenreCatalog.display('   '), isNull);
    expect(GenreCatalog.display(null), isNull);
  });

  test('display uses the category for an alias', () {
    expect(GenreCatalog.display('hip hop'), 'Hip-Hop/Rap');
    expect(GenreCatalog.display('Pop'), 'Pop');
  });

  test('REF-17: an online genre is suggested only when its votes name one '
      'category', () {
    expect(GenreCatalog.fromVotes([('hip hop', 7), ('pop', 2)]), 'Hip-Hop/Rap');
    expect(
      GenreCatalog.fromVotes([('hip hop', 5), ('rap', 5), ('pop', 1)]),
      'Hip-Hop/Rap',
      reason: 'tied, but the same category',
    );
    expect(
      GenreCatalog.fromVotes([('pop', 4), ('rock', 4)]),
      isNull,
      reason: 'tied between categories: ambiguous',
    );
    expect(
      GenreCatalog.fromVotes([('pop rock', 9), ('pop', 3)]),
      isNull,
      reason: 'the most-voted genre is not a category; never guessed',
    );
    expect(GenreCatalog.fromVotes(const []), isNull);
    expect(GenreCatalog.fromVotes([(' ', 3)]), isNull);
  });

  test('suggestions put the exact category first, then matches', () {
    expect(GenreCatalog.suggestionsFor('rnb').first, 'R&B/Soul');
    expect(GenreCatalog.suggestionsFor('hip').first, 'Hip-Hop/Rap');
    expect(GenreCatalog.suggestionsFor('ro'), containsAll(['Rock']));
    expect(GenreCatalog.suggestionsFor(''), GenreCatalog.categories);
  });

  test(
    "the release's own genres are offered, without repeating categories",
    () {
      final all = GenreCatalog.suggestionsFor(
        '',
        known: ['Hyperpop', 'hip hop', 'Hyperpop ', ''],
      );
      expect(all.where((g) => g == 'Hyperpop'), hasLength(1));
      expect(all, isNot(contains('hip hop')), reason: 'an alias of a category');
      expect(GenreCatalog.suggestionsFor('hyper', known: ['Hyperpop']), [
        'Hyperpop',
      ]);
    },
  );
}
