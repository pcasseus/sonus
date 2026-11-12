/// Canonical genre categories and the common ways they are written
/// (App Update 1.2, REF-14).
///
/// Used to suggest a genre while editing and to show a stored genre under
/// its canonical name. It never writes anything: a genre stays stored as it
/// was saved, and only a listener's own choice changes it. Only exact
/// aliases map to a category ("hip hop", "R&B"); anything else, such as
/// "Pop Rock" or "Indie Folk", is shown as written rather than guessed.
abstract final class GenreCatalog {
  /// The suggested categories, in the order they are offered.
  static const List<String> categories = [
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
  ];

  /// Spellings that mean exactly one category, by their [_key].
  static final Map<String, String> _aliases = {
    for (final category in categories) _key(category): category,
    for (final alias in ['pop music', 'pop/pop']) _key(alias): 'Pop',
    for (final alias in [
      'hip hop',
      'hip-hop',
      'hiphop',
      'rap',
      'hip hop/rap',
      'rap/hip hop',
      'rap/hip-hop',
      'hip-hop & rap',
      'hip hop & rap',
    ])
      _key(alias): 'Hip-Hop/Rap',
    for (final alias in [
      'r&b',
      'rnb',
      'r & b',
      'r and b',
      'rhythm and blues',
      'rhythm & blues',
      'soul',
      'r&b soul',
      'r&b & soul',
      'soul/r&b',
      'contemporary r&b',
    ])
      _key(alias): 'R&B/Soul',
    for (final alias in ['rock music', 'rock & roll', 'rock and roll'])
      _key(alias): 'Rock',
    for (final alias in ['alternative rock', 'alt rock', 'alt-rock', 'alt'])
      _key(alias): 'Alternative',
    for (final alias in [
      'dance',
      'electronic',
      'electronica',
      'edm',
      'electronic dance music',
      'dance & electronic',
      'electronic/dance',
    ])
      _key(alias): 'Dance/Electronic',
    for (final alias in ['country music']) _key(alias): 'Country',
    for (final alias in ['latin music', 'latino', 'musica latina'])
      _key(alias): 'Latin',
    for (final alias in ['reggae', 'dancehall', 'dancehall/reggae'])
      _key(alias): 'Reggae/Dancehall',
    for (final alias in ['afrobeat', 'afro beats', 'afro-beats', 'afropop'])
      _key(alias): 'Afrobeats',
    for (final alias in ['gospel music', 'christian & gospel'])
      _key(alias): 'Gospel',
    for (final alias in ['folk music']) _key(alias): 'Folk',
    for (final alias in ['heavy metal']) _key(alias): 'Metal',
    for (final alias in [
      'soundtracks',
      'original soundtrack',
      'ost',
      'film score',
    ])
      _key(alias): 'Soundtrack',
  };

  /// The category [genre] is an exact alias of, or null when it is not one
  /// (unknown, ambiguous or blank).
  static String? canonicalOf(String? genre) {
    final key = _key(genre ?? '');
    return key.isEmpty ? null : _aliases[key];
  }

  /// [genre] as shown: its category when it is an exact alias, otherwise
  /// the stored text, trimmed. Null when blank.
  static String? display(String? genre) {
    final trimmed = genre?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return canonicalOf(trimmed) ?? trimmed;
  }

  /// Suggestions for what the listener is typing: the category it is an
  /// alias of first, then categories and [known] genres containing it.
  /// Everything when [query] is blank.
  static List<String> suggestionsFor(
    String query, {
    Iterable<String> known = const [],
  }) {
    final key = _key(query);
    final pool = <String>[
      ...categories,
      for (final genre in known)
        if (genre.trim().isNotEmpty && canonicalOf(genre) == null) genre.trim(),
    ];
    final unique = <String>[];
    final seen = <String>{};
    for (final genre in pool) {
      if (seen.add(_key(genre))) unique.add(genre);
    }
    if (key.isEmpty) return unique;

    final exact = _aliases[key];
    return [
      ?exact,
      for (final genre in unique)
        if (genre != exact && _key(genre).contains(key)) genre,
    ];
  }

  /// Lower case, "and" for "&", separators as single spaces.
  static String _key(String text) => text
      .toLowerCase()
      .replaceAll(' and ', ' & ')
      .replaceAll(RegExp(r'[\s_\-/]+'), ' ')
      .replaceAll(RegExp(r'\s*&\s*'), '&')
      .trim();
}
