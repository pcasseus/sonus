import '../../application/models/song_credit_line.dart';
import '../../domain/entities/library_organization.dart';

/// UI redesign C2 (D10): credit lines naming more performers than this
/// collapse to a summary on soundtracks and cast recordings.
const int compactCreditMaxNames = 3;

/// How many names a collapsed credit line still shows, in credit order.
const int compactCreditShownNames = 2;

/// The release kinds whose track rows may collapse long credit lines.
/// Ordinary and unclassified releases always show the full line.
const Set<ReleaseKind> compactCreditReleaseKinds = {
  ReleaseKind.soundtrack,
  ReleaseKind.castRecording,
};

/// A song's credit line, with a compact form when it names more than
/// [compactCreditMaxNames] performers. Presentation only: the credits
/// themselves are never changed.
class SongCreditSummary {
  const SongCreditSummary({
    required this.full,
    this.compact,
    this.hiddenCount = 0,
  });

  /// Exactly [songCreditLine]'s text.
  final String full;

  /// For example "Ft. Ada, Ben + 3 others"; null when the line is short
  /// enough to show whole.
  final String? compact;

  /// Names left out of [compact].
  final int hiddenCount;

  bool get isCollapsible => compact != null;
}

/// See [SongCreditSummary]. Takes the same arguments as [songCreditLine]
/// and keeps its role connectors ("&", "Ft.", "with") for the names shown.
SongCreditSummary songCreditSummary({
  required String primaryArtistName,
  List<String> coPrimaryArtists = const [],
  List<String> featuredArtists = const [],
  List<String> guestArtists = const [],
  bool omitPrimary = false,
}) {
  final full = songCreditLine(
    primaryArtistName: primaryArtistName,
    coPrimaryArtists: coPrimaryArtists,
    featuredArtists: featuredArtists,
    guestArtists: guestArtists,
    omitPrimary: omitPrimary,
  );

  final leads = _cleaned([primaryArtistName, ...coPrimaryArtists]);
  final featured = _cleaned(featuredArtists);
  final guests = _cleaned(guestArtists);
  final showLeads = !omitPrimary || leads.length > 1;
  final shownLeads = showLeads ? leads : const <String>[];
  final total = shownLeads.length + featured.length + guests.length;

  if (total <= compactCreditMaxNames) {
    return SongCreditSummary(full: full);
  }

  var budget = compactCreditShownNames;
  List<String> take(List<String> names) {
    final taken = names.take(budget).toList(growable: false);
    budget -= taken.length;
    return taken;
  }

  final keptLeads = take(shownLeads);
  final keptFeatured = take(featured);
  final keptGuests = take(guests);
  final hidden = total - compactCreditShownNames;

  final shown = songCreditLine(
    primaryArtistName: keptLeads.isEmpty ? '' : keptLeads.first,
    coPrimaryArtists: keptLeads.skip(1).toList(growable: false),
    featuredArtists: keptFeatured,
    guestArtists: keptGuests,
    omitPrimary: omitPrimary,
  );

  return SongCreditSummary(
    full: full,
    compact: '$shown + $hidden ${hidden == 1 ? 'other' : 'others'}',
    hiddenCount: hidden,
  );
}

List<String> _cleaned(List<String> names) => [
  for (final name in names)
    if (name.trim().isNotEmpty) name.trim(),
];
