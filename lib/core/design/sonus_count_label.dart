/// The noun for a count: [singular] for exactly one, otherwise [plural]
/// (by default [singular] plus "s"). Keeps labels such as "1 stream" and
/// "1 weekly stream" grammatical, on screen and for screen readers.
String sonusCountNoun(int count, String singular, {String? plural}) =>
    count == 1 ? singular : plural ?? '${singular}s';

/// "[count] [noun]", with the noun from [sonusCountNoun].
String sonusCount(int count, String singular, {String? plural}) =>
    '$count ${sonusCountNoun(count, singular, plural: plural)}';
