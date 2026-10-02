abstract final class DatabaseTables {
  static const String artists = 'artists';
  static const String albums = 'albums';
  static const String albumEditions = 'album_editions';
  static const String albumEditionTracks = 'album_edition_tracks';
  static const String songs = 'songs';
  static const String songArtistCredits = 'song_artist_credits';
  static const String mediaFileBindings = 'media_file_bindings';
  static const String importBatches = 'import_batches';
  static const String importSources = 'import_sources';
  static const String songImportReviews = 'song_import_reviews';
  static const String trackLyrics = 'track_lyrics';
  static const String artworkAssets = 'artwork_assets';

  static const String playbackSessions = 'playback_sessions';
  static const String playbackListeningSegments = 'playback_listening_segments';
  static const String qualifiedPlays = 'qualified_plays';

  static const String chartSnapshots = 'chart_snapshots';
  static const String chartEntries = 'chart_entries';
  static const String chartMomentEvents = 'chart_moment_events';

  static const String playlists = 'playlists';
  static const String playlistItems = 'playlist_items';

  static const String syncState = 'sync_state';
  static const String syncOutbox = 'sync_outbox';
}
