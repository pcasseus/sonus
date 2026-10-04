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
