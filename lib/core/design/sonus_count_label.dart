/// The noun for a count: [singular] for exactly one, otherwise [plural]
/// (by default [singular] plus "s"). Keeps labels such as "1 stream" and
/// "1 weekly stream" grammatical, on screen and for screen readers.
String sonusCountNoun(int count, String singular, {String? plural}) =>
    count == 1 ? singular : plural ?? '${singular}s';

/// "[count] [noun]", with the noun from [sonusCountNoun].
String sonusCount(int count, String singular, {String? plural}) =>
    '$count ${sonusCountNoun(count, singular, plural: plural)}';

/// A listening time such as "45 min", "2h" or "1h 58m". Under a minute
/// reads "under a minute" rather than a rounded "0 min".
String sonusListeningTime(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return 'under a minute';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
