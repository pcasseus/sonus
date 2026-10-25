/// Where each letter starts in an alphabetically sorted list (SN-45 Tracks
/// fast scroll). Titles that start with a digit or symbol share '#'.
class AlphabetIndex {
  const AlphabetIndex._(this._firstIndex);

  /// Builds the index from each row's sort key, in list order. One pass,
  /// so it stays cheap for libraries of thousands of songs.
  factory AlphabetIndex.build(Iterable<String> sortKeys) {
    final first = <String, int>{};
    var index = 0;
    for (final key in sortKeys) {
      first.putIfAbsent(letterOf(key), () => index);
      index++;
    }
    return AlphabetIndex._(first);
  }

  static const String other = '#';

  static const List<String> letters = [
    other,
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  final Map<String, int> _firstIndex;

  /// Letters that have at least one row.
  Set<String> get available => _firstIndex.keys.toSet();

  bool get isUseful => _firstIndex.length > 1;

  /// The row to jump to for [letter]: its first row, or the next letter's
  /// when it has none, or the last letter's before it at the end.
  int? indexFor(String letter) {
    final position = letters.indexOf(letter);
    if (position == -1 || _firstIndex.isEmpty) return null;

    for (var i = position; i < letters.length; i++) {
      final found = _firstIndex[letters[i]];
      if (found != null) return found;
    }
    for (var i = position - 1; i >= 0; i--) {
      final found = _firstIndex[letters[i]];
      if (found != null) return found;
    }
    return null;
  }

  /// The letter a row with [sortKey] is filed under.
  static String letterOf(String sortKey) {
    for (final rune in sortKey.trim().runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) continue;
      final folded = _fold(char.toUpperCase());
      return letters.contains(folded) && folded != other ? folded : other;
    }
    return other;
  }

  static String _fold(String char) => _accents[char] ?? char;

  static const Map<String, String> _accents = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Æ': 'A', //
    'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ì': 'I', 'Í': 'I', //
    'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', //
    'Ö': 'O', 'Ø': 'O', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y', //
    'Ÿ': 'Y', 'Š': 'S', 'Ž': 'Z', 'Œ': 'O',
  };
}
