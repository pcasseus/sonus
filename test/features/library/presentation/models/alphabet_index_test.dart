import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/presentation/models/alphabet_index.dart';

void main() {
  test('letters, accents and symbols', () {
    expect(AlphabetIndex.letterOf('angel wings'), 'A');
    expect(AlphabetIndex.letterOf('  Bittersweet'), 'B');
    expect(AlphabetIndex.letterOf('Élan'), 'E');
    expect(AlphabetIndex.letterOf('Øyvind'), 'O');
    expect(AlphabetIndex.letterOf('7 rings'), '#');
    expect(AlphabetIndex.letterOf('(intro)'), '#');
    expect(AlphabetIndex.letterOf('夜に駆ける'), '#');
    expect(AlphabetIndex.letterOf(''), '#');
  });

  test('first rows per letter in list order', () {
    final index = AlphabetIndex.build([
      '1999',
      'angel',
      'Apple',
      'bitter',
      'locket',
      'Lost',
    ]);

    expect(index.indexFor('#'), 0);
    expect(index.indexFor('A'), 1);
    expect(index.indexFor('B'), 3);
    expect(index.indexFor('L'), 4);
    expect(index.available, {'#', 'A', 'B', 'L'});
    expect(index.isUseful, isTrue);
  });

  test('an empty letter jumps to the next one, or the last before it', () {
    final index = AlphabetIndex.build(['apple', 'mango', 'melon']);

    expect(index.indexFor('C'), 1, reason: 'next with rows is M');
    expect(index.indexFor('Z'), 1, reason: 'nothing after: last before');
    expect(index.indexFor('?'), isNull);
  });

  test('one letter is not worth a rail', () {
    expect(AlphabetIndex.build(['apple', 'avocado']).isUseful, isFalse);
  });

  test('thousands of rows index in one pass', () {
    final keys = [for (var i = 0; i < 20000; i++) 'Song ${i % 26}'];
    final watch = Stopwatch()..start();
    final index = AlphabetIndex.build(keys);
    watch.stop();

    expect(index.indexFor('S'), 0);
    expect(watch.elapsedMilliseconds, lessThan(200));
  });
}
