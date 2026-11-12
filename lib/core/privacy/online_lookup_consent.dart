/// Whether the user has seen and accepted what online metadata lookups
/// share, before Sonus contacts MusicBrainz for the first time. Import and
/// everything else stays offline either way.
abstract interface class OnlineLookupConsent {
  bool get isOnlineLookupAccepted;

  Future<void> acceptOnlineLookup();
}

/// What an online lookup sends, shown before the first one.
const onlineLookupDisclosure =
    'To find metadata, Sonus sends the search text (an artist, album or song '
    'name, and for songs the album and length) to MusicBrainz. Nothing else '
    'from your library '
    'leaves this device, and nothing changes until you choose a result. '
    'You can turn online lookups off in Settings.';
