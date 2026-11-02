class ExplicitFeatureCredit {
  const ExplicitFeatureCredit({
    required this.primaryArtist,
    required this.featuredArtist,
  });

  final String primaryArtist;
  final String featuredArtist;
}

class ArtistCreditParser {
  const ArtistCreditParser();

  /// Splits a comma-separated list of artist names, keeping a name that
  /// itself contains commas, such as "Crane, The Lantern", whole when it
  /// matches one of [knownNames] (compared ignoring case and the spacing
  /// around commas). The longest known name wins; other parts split at
  /// each comma. Blank parts are dropped.
  List<String> splitNameList(
    String text, {
    Iterable<String> knownNames = const [],
  }) {
    final known = {
      for (final name in knownNames)
        if (name.contains(',')) _commaCanonical(name),
    };
    final parts = text.split(',').map((part) => part.trim()).toList();
    final names = <String>[];
    var start = 0;

    while (start < parts.length) {
      if (parts[start].isEmpty) {
        start++;
        continue;
      }

      var end = start + 1;

      for (
        var candidateEnd = parts.length;
        candidateEnd > end;
        candidateEnd--
      ) {
        final candidate = parts.sublist(start, candidateEnd).join(', ');

        if (known.contains(_commaCanonical(candidate))) {
          end = candidateEnd;
          break;
        }
      }

      names.add(parts.sublist(start, end).join(', '));
      start = end;
    }

    return List<String>.unmodifiable(names);
  }

  static String _commaCanonical(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s*,\s*'), ', ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  ExplicitFeatureCredit? parseExplicitFeatureCredit(String rawCredit) {
    final cleaned = rawCredit.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    final wrappedMatch = RegExp(
      r'^(.*?)\s*[\[(]\s*(?:feat\.?|ft\.?|featuring)\s+(.+?)\s*[\])]$',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (wrappedMatch != null) {
      return _featureCreditFromMatch(wrappedMatch);
    }

    final directMatch = RegExp(
      r'^(.*?)\s+(?:feat\.?|ft\.?|featuring)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(cleaned);

    if (directMatch == null) {
      return null;
    }

    return _featureCreditFromMatch(directMatch);
  }

  ExplicitFeatureCredit? _featureCreditFromMatch(RegExpMatch match) {
    final primaryArtist = match.group(1)?.trim() ?? '';
    final featuredArtist = match.group(2)?.trim() ?? '';

    if (primaryArtist.isEmpty || featuredArtist.isEmpty) {
      return null;
    }

    return ExplicitFeatureCredit(
      primaryArtist: primaryArtist,
      featuredArtist: featuredArtist,
    );
  }
}
