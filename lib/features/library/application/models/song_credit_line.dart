/// A song's role-aware performer line (SN-50 C-Q1, B-Q15/B-Q32):
/// the primary and co-primary artists joined with " & ", then featured
/// artists after "Ft.", then guests after "with", each list joined with
/// ", ". For example "Ada & Ben Ft. Cy, Dee with Eve". Every
/// screen shows the featured connector as "Ft." (SN-50 BUG-05); imports
/// still read "feat.", "ft." and "featuring".
///
/// With [omitPrimary] (rows on a page that already names the artist, such
/// as an Album page) the leading names are left out unless the song has
/// co-primary artists, giving "Ft. Cy with Eve" or an empty string.
String songCreditLine({
  required String primaryArtistName,
  List<String> coPrimaryArtists = const [],
  List<String> featuredArtists = const [],
  List<String> guestArtists = const [],
  bool omitPrimary = false,
}) {
  final leads = _cleaned([primaryArtistName, ...coPrimaryArtists]);
  final featured = _cleaned(featuredArtists);
  final guests = _cleaned(guestArtists);
  final showLeads = !omitPrimary || leads.length > 1;

  return [
    if (showLeads && leads.isNotEmpty) leads.join(' & '),
    if (featured.isNotEmpty) 'Ft. ${featured.join(', ')}',
    if (guests.isNotEmpty) 'with ${guests.join(', ')}',
  ].join(' ');
}

List<String> _cleaned(List<String> names) {
  return [
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
}
