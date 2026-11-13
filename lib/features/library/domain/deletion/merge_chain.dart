/// App Update 1.2: where merged records went, following every step.
///
/// A merge maps a duplicate's id to the id that stayed. Merges can build on
/// each other (A merged into B, later B into C), so a merged id resolves to
/// the end of its chain: A → B → C gives C, never B, which no longer
/// exists.
///
/// A chain that loops (A → B → A) or names an empty id cannot be resolved:
/// [MergeChainException] is thrown, so the caller refuses the whole
/// operation instead of guessing or writing history that points nowhere.
class MergeChainException implements Exception {
  const MergeChainException(this.kind, this.chain);

  /// 'songs', 'editions' or 'albums'.
  final String kind;

  /// The ids walked before the chain proved invalid.
  final List<String> chain;

  @override
  String toString() =>
      'MergeChainException: the $kind merge chain '
      '${chain.join(' → ')} cannot be resolved';
}

class MergeChains {
  MergeChains({
    Map<String, String> songs = const {},
    Map<String, String> editions = const {},
    Map<String, String> albums = const {},
  }) : _maps = {'songs': songs, 'editions': editions, 'albums': albums};

  static const kinds = ['songs', 'editions', 'albums'];

  final Map<String, Map<String, String>> _maps;
  final Map<String, Map<String, List<String>>> _paths = {};

  bool get isEmpty => _maps.values.every((map) => map.isEmpty);

  /// Whether [id] was merged into another record (directly).
  bool isMerged(String kind, String id) => _map(kind).containsKey(id);

  /// [id] followed by every id it was merged into, in order; the last is
  /// the record that stayed. Just `[id]` for an id that was never merged.
  ///
  /// Throws [MergeChainException] for a loop or an empty id in the chain.
  List<String> path(String kind, String id) {
    final cache = _paths[kind] ??= {};
    final cached = cache[id];
    if (cached != null) return cached;

    final map = _map(kind);
    if (id.isEmpty) throw MergeChainException(kind, [id]);
    final walked = <String>[id];
    final seen = <String>{id};
    var current = id;
    while (true) {
      final next = map[current];
      if (next == null) break;
      if (next.isEmpty || !seen.add(next)) {
        throw MergeChainException(kind, [...walked, next]);
      }
      walked.add(next);
      current = next;
    }
    return cache[id] = List.unmodifiable(walked);
  }

  /// The record [id] ends up as. Throws [MergeChainException] when the
  /// chain cannot be resolved.
  String resolve(String kind, String id) => path(kind, id).last;

  /// [resolve] for a nullable column value: null and non-strings stay null.
  String? resolveValue(String kind, Object? id) =>
      id is String ? resolve(kind, id) : null;

  /// Whether any id on [id]'s chain is in [ids] (for example, the songs the
  /// user permanently deleted: history of a duplicate merged into a song
  /// that was later deleted is deleted history too).
  bool chainHitsAny(String kind, Object? id, Set<String> ids) {
    if (id is! String || ids.isEmpty) return false;
    return path(kind, id).any(ids.contains);
  }

  Map<String, String> _map(String kind) {
    final map = _maps[kind];
    if (map == null) throw ArgumentError.value(kind, 'kind');
    return map;
  }
}
