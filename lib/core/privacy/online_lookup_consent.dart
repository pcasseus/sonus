/// Whether the user has seen and accepted what online metadata lookups
/// share, before Sonus contacts MusicBrainz for the first time. Import and
/// everything else stays offline either way.
abstract interface class OnlineLookupConsent {
  bool get isOnlineLookupAccepted;

  Future<void> acceptOnlineLookup();
}

/// What online lookups do and what they send, shown before the first one.
///
/// Each statement matches the implementation: Artist, Release and Track
/// Studio offer the lookups, an album lookup can propose a genre, nothing is
/// applied until the user chooses, and an external value never replaces a
/// manual one (`MetadataAuthorityPolicy`).
const onlineLookupDisclosure =
    'MusicBrainz can suggest artist, release and song information, and genres '
    'for albums. Review the suggestions before applying them. Your manual '
    'edits will not be replaced automatically.\n\n'
    'To search, Sonus sends only the search text (an artist, album or song '
    'name, and for songs the album and length) to MusicBrainz. Nothing else '
    'from your library leaves this device. You can turn online lookups off in '
    'Settings.';
