import 'package:uuid/uuid.dart';

abstract final class EntityId {
  static const Uuid _uuid = Uuid();

  static String artist() => 'artist_${_uuid.v4()}';

  static String album() => 'album_${_uuid.v4()}';

  static String albumEdition() => 'edition_${_uuid.v4()}';

  static String song() => 'song_${_uuid.v4()}';

  static String mediaFileBinding() => 'media_${_uuid.v4()}';

  static String importBatch() => 'import_batch_${_uuid.v4()}';

  static String importSource() => 'import_source_${_uuid.v4()}';

  static String artworkAsset() => 'artwork_${_uuid.v4()}';

  static String playlist() => 'playlist_${_uuid.v4()}';

  static String playlistItem() => 'playlist_item_${_uuid.v4()}';

  static String playbackSession() => 'session_${_uuid.v4()}';

  static String listeningSegment() => 'segment_${_uuid.v4()}';

  static String qualifiedPlay() => 'play_${_uuid.v4()}';

  static String syncOutbox() => 'sync_outbox_${_uuid.v4()}';
}
