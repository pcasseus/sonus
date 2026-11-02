// ignore_for_file: prefer_initializing_formals, use_super_parameters

import 'dart:math';

import 'package:just_audio/just_audio.dart';

/// Sonus's shuffle order (SN-50 device QA): within one shuffle cycle, no
/// queue entry plays twice on its own.
///
/// just_audio's [DefaultShuffleOrder] reshuffles every entry when shuffle is
/// turned on (entries already played come round again), places a moved
/// entry anywhere in the order (a played one can come up again), and an
/// explicit jump plays on from wherever the chosen entry happens to sit.
/// This order keeps the play history instead:
///
/// - [arrange] gives the next [shuffle] an exact order, so the engine can
///   keep played entries first when shuffle is turned on, and put an entry
///   the listener chose right after the current one.
/// - Inserted entries go after the current one: right after it when the
///   insert is right after the current entry (Play next), otherwise at a
///   random later place. Never among the played.
/// - A move ([beginMove]) keeps the entry's place in the play order.
/// - A saved order is restored exactly on the first load (SN-50 #24),
///   including through the shuffle just_audio applies to every load.
///
/// Everything else (Repeat All starting the cycle again, Repeat One) is
/// just_audio's own behaviour.
class SonusShuffleOrder extends DefaultShuffleOrder {
  SonusShuffleOrder({
    List<int>? saved,
    int? Function()? currentIndex,
    Random? random,
  }) : _saved = saved == null ? null : List.of(saved),
       _currentIndex = currentIndex,
       _rng = random ?? Random(),
       super(random: random);

  List<int>? _saved;
  final int? Function()? _currentIndex;
  final Random _rng;

  List<int>? _arrangement;

  /// A saved order was restored: just_audio shuffles every source it
  /// loads, and that first shuffle must keep it.
  bool _keepRestored = false;
  bool _moving = false;
  int? _movedFrom;

  /// The order the next [shuffle] applies, if it is a permutation of the
  /// current indices; otherwise that shuffle behaves as before.
  void arrange(List<int> order) => _arrangement = List.of(order);

  /// The next remove-and-insert pair is a move: the entry keeps its place.
  void beginMove() {
    _moving = true;
    _movedFrom = null;
  }

  @override
  void shuffle({int? initialIndex}) {
    if (_keepRestored) {
      _keepRestored = false;
      return;
    }
    final arranged = _arrangement;
    _arrangement = null;
    if (arranged != null && _isPermutation(arranged)) {
      indices
        ..clear()
        ..addAll(arranged);
      return;
    }
    super.shuffle(initialIndex: initialIndex);
  }

  @override
  void insert(int index, int count) {
    final saved = _saved;
    if (saved != null && indices.isEmpty && index == 0) {
      _saved = null;
      if (count == saved.length) {
        indices.addAll(saved);
        _keepRestored = true;
        return;
      }
    }

    final movedFrom = _movedFrom;
    if (_moving && movedFrom != null && count == 1) {
      _moving = false;
      _movedFrom = null;
      _shift(index, count);
      indices.insert(movedFrom.clamp(0, indices.length), index);
      return;
    }
    _moving = false;

    // The current entry, before this insert shifts it.
    var current = indices.isEmpty ? null : _currentIndex?.call();
    if (current == null || !indices.contains(current)) {
      super.insert(index, count);
      return;
    }
    // Right after the current entry in the queue: Play next.
    final playNext = index == current + 1;
    if (current >= index) current += count;
    _shift(index, count);

    final after = indices.indexOf(current) + 1;
    for (var i = 0; i < count; i++) {
      final position = playNext
          ? after + i
          : after + _rng.nextInt(indices.length - after + 1);
      indices.insert(position, index + i);
    }
  }

  @override
  void removeRange(int start, int end) {
    if (_moving && end - start == 1) {
      _movedFrom = indices.indexOf(start);
    }
    super.removeRange(start, end);
  }

  @override
  void clear() {
    _arrangement = null;
    _keepRestored = false;
    _moving = false;
    _movedFrom = null;
    super.clear();
  }

  void _shift(int index, int count) {
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
  }

  bool _isPermutation(List<int> order) {
    if (order.length != indices.length) return false;
    final seen = <int>{};
    for (final i in order) {
      if (i < 0 || i >= indices.length || !seen.add(i)) return false;
    }
    return true;
  }
}

/// Queue indices already played in the current cycle: those before the
/// current entry in play order (the shuffle order while shuffle is on, the
/// queue's own order otherwise). Per entry, so a song queued twice is
/// played once and upcoming once. Repeat All starts a new cycle when it
/// wraps; picking an earlier entry (with shuffle off) replays from there.
Set<int> playedQueueIndices({
  required int length,
  required int currentIndex,
  List<int>? shuffleOrder,
}) {
  if (currentIndex < 0 || currentIndex >= length) return const {};
  final order = shuffleOrder != null && shuffleOrder.length == length
      ? shuffleOrder
      : [for (var i = 0; i < length; i++) i];
  final position = order.indexOf(currentIndex);
  if (position < 0) return const {};
  return {for (var i = 0; i < position; i++) order[i]};
}

/// The play order after the listener picks [target] while shuffled: the
/// current entry and everything before it stay played, [target] plays
/// next, and every other upcoming entry keeps its place.
List<int> orderPlayingNext(
  List<int> order, {
  required int current,
  required int target,
}) {
  if (target == current) return List.of(order);
  final result = [...order]..remove(target);
  final at = result.indexOf(current);
  if (at < 0) return List.of(order);
  result.insert(at + 1, target);
  return result;
}

/// The play order when shuffle is turned on at [current] in queue order:
/// the entries already played keep their order, then the current one, then
/// every other entry shuffled.
List<int> orderKeepingPlayed(
  int length, {
  required int current,
  Random? random,
}) {
  final played = [for (var i = 0; i < current; i++) i];
  final rest = [for (var i = current + 1; i < length; i++) i]..shuffle(random);
  return [...played, current, ...rest];
}
