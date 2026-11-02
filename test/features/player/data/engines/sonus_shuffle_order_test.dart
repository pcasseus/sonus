// SN-50 device QA: with Shuffle on, no queue entry plays twice on its own
// within one cycle.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/data/engines/support/sonus_shuffle_order.dart';

SonusShuffleOrder _order(int length, {int? Function()? current, int seed = 3}) {
  final order = SonusShuffleOrder(currentIndex: current, random: Random(seed));
  order.insert(0, length);
  return order;
}

void main() {
  group('SonusShuffleOrder', () {
    test('an arranged shuffle keeps played entries first', () {
      final order = _order(8);
      order.arrange(orderKeepingPlayed(8, current: 3, random: Random(1)));
      order.shuffle(initialIndex: 3);

      expect(order.indices.take(4), [0, 1, 2, 3]);
      expect(order.indices.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
      expect(
        playedQueueIndices(
          length: 8,
          currentIndex: 3,
          shuffleOrder: order.indices,
        ),
        {0, 1, 2},
      );
    });

    test('an arrangement that is not a permutation is ignored', () {
      final order = _order(4);
      order.arrange([0, 0, 1, 2]);
      order.shuffle(initialIndex: 2);
      expect(order.indices.first, 2);
      expect(order.indices.toSet(), {0, 1, 2, 3});
    });

    test('inserted entries never land among the played', () {
      for (var seed = 0; seed < 40; seed++) {
        var current = 4;
        final order = SonusShuffleOrder(
          saved: [5, 2, 7, 4, 0, 1, 3, 6],
          currentIndex: () => current,
          random: Random(seed),
        )..insert(0, 8);
        final playedBefore = playedQueueIndices(
          length: 8,
          currentIndex: current,
          shuffleOrder: order.indices,
        );

        order.insert(8, 1); // Add to queue (end of the queue).
        final played = playedQueueIndices(
          length: 9,
          currentIndex: current,
          shuffleOrder: order.indices,
        );
        expect(played, playedBefore, reason: 'seed $seed');
        expect(played.contains(8), isFalse);
      }
    });

    test('Play next goes right after the current entry', () {
      var current = 4;
      final order = SonusShuffleOrder(
        saved: [5, 2, 7, 4, 0, 1, 3, 6],
        currentIndex: () => current,
        random: Random(2),
      )..insert(0, 8);

      order.insert(5, 1); // right after the current entry in the queue
      // Queue indices from 5 shift by one; the new entry is 5.
      expect(order.indices, [6, 2, 8, 4, 5, 0, 1, 3, 7]);
    });

    test('a moved entry keeps its place in the play order', () {
      final order = SonusShuffleOrder(saved: [5, 2, 7, 4, 0, 1, 3, 6])
        ..insert(0, 8);
      final played = playedQueueIndices(
        length: 8,
        currentIndex: 4,
        shuffleOrder: order.indices,
      );
      expect(played, {5, 2, 7});

      // Move queue entry 2 (played) to the end, as just_audio does it.
      order
        ..beginMove()
        ..removeRange(2, 3)
        ..insert(7, 1);
      // Entries 3..7 moved up by one; the moved entry is now 7.
      final after = playedQueueIndices(
        length: 8,
        currentIndex: 3,
        shuffleOrder: order.indices,
      );
      expect(after, {4, 7, 6});
      expect(order.indices.length, 8);
    });

    test('a saved order is restored exactly', () {
      final order = SonusShuffleOrder(saved: [3, 1, 0, 2])..insert(0, 4);
      expect(order.indices, [3, 1, 0, 2]);
    });
  });

  group('play order helpers', () {
    test('picking an entry plays it next; nothing played comes back', () {
      final order = [5, 2, 7, 4, 0, 1, 3, 6];
      // Current is 4 (position 3); pick 2, which already played.
      final next = orderPlayingNext(order, current: 4, target: 2);
      expect(next, [5, 7, 4, 2, 0, 1, 3, 6]);
      // Once 2 is current, 5, 7 and 4 are played; 0, 1, 3, 6 still to come.
      expect(
        playedQueueIndices(length: 8, currentIndex: 2, shuffleOrder: next),
        {5, 7, 4},
      );

      // Picking an upcoming entry skips none of the others.
      final forward = orderPlayingNext(order, current: 4, target: 6);
      expect(forward, [5, 2, 7, 4, 6, 0, 1, 3]);
    });

    test('played per entry: a song queued twice is played once', () {
      // Queue order, shuffle off: entries 0 and 2 are the same song.
      expect(playedQueueIndices(length: 4, currentIndex: 1), {0});
      expect(playedQueueIndices(length: 4, currentIndex: 3), {0, 1, 2});
      // Repeat All wrapped round: a new cycle, nothing played yet.
      expect(playedQueueIndices(length: 4, currentIndex: 0), isEmpty);
      expect(playedQueueIndices(length: 0, currentIndex: -1), isEmpty);
    });
  });
}
