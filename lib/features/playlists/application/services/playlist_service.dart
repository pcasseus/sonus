import '../../../../core/identity/entity_id.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../sync/application/services/sync_mutation_context.dart';
import '../../../sync/application/services/sync_mutation_runner.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/playlist_item.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../models/playlist_detail.dart';
import '../models/playlist_summary.dart';
import '../models/playlist_track.dart';

typedef PlaylistIdGenerator = String Function();
typedef PlaylistItemIdGenerator = String Function();
typedef PlaylistClock = DateTime Function();

class PlaylistService {
  PlaylistService({
    required this.repository,
    required this.library,
    required this.mutationRunner,
    PlaylistIdGenerator? generatePlaylistId,
    PlaylistItemIdGenerator? generatePlaylistItemId,
    PlaylistClock? now,
  }) : _generatePlaylistId = generatePlaylistId ?? EntityId.playlist,
       _generatePlaylistItemId =
           generatePlaylistItemId ?? EntityId.playlistItem,
       _now = now ?? DateTime.now;

  final PlaylistRepository repository;
  final LibraryQueryRepository library;
  final SyncMutationRunner mutationRunner;

  final PlaylistIdGenerator _generatePlaylistId;
  final PlaylistItemIdGenerator _generatePlaylistItemId;
  final PlaylistClock _now;

  Future<List<PlaylistSummary>> getPlaylists() async {
    final playlists = await repository.getAll();
    final tracks = await library.getTracks();

    final tracksById = {for (final track in tracks) track.songId: track};

    final summaries = <PlaylistSummary>[];

    for (final playlist in playlists) {
      final items = await repository.getItems(playlist.id);

      final visibleTrackCount = items.where((item) {
        final track = tracksById[item.songId];

        return track != null && _hasAvailableMedia(track);
      }).length;

      summaries.add(
        PlaylistSummary(playlist: playlist, trackCount: visibleTrackCount),
      );
    }

    return List<PlaylistSummary>.unmodifiable(summaries);
  }

  Future<PlaylistDetail> getPlaylist(String playlistId) async {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    final playlist = await repository.getById(normalizedPlaylistId);

    if (playlist == null) {
      throw StateError('Playlist not found: $normalizedPlaylistId');
    }

    final items = await repository.getItems(normalizedPlaylistId);
    final tracks = <PlaylistTrack>[];

    for (final item in items) {
      final track = await library.getTrackById(item.songId);

      if (track == null) {
        throw StateError(
          'Playlist item ${item.id} points to missing song ${item.songId}.',
        );
      }

      tracks.add(PlaylistTrack(item: item, track: track));
    }

    return PlaylistDetail(
      playlist: playlist,
      tracks: List<PlaylistTrack>.unmodifiable(tracks),
    );
  }

  Future<Playlist> createPlaylist({required String name, DateTime? now}) {
    final trimmedName = _requiredName(name);
    final timestamp = now ?? _now();

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = Playlist(
        id: _generatePlaylistId(),
        name: trimmedName,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      await playlistRepository.create(playlist);

      return playlist;
    });
  }

  Future<Playlist> renamePlaylist({
    required String playlistId,
    required String name,
    DateTime? now,
  }) {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    final trimmedName = _requiredName(name);
    final timestamp = now ?? _now();

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = await playlistRepository.getById(normalizedPlaylistId);

      if (playlist == null) {
        throw StateError('Playlist not found: $normalizedPlaylistId');
      }

      if (playlist.name == trimmedName) {
        return playlist;
      }

      final updated = playlist.copyWith(
        name: trimmedName,
        updatedAt: timestamp,
      );

      await playlistRepository.save(updated);

      return updated;
    });
  }

  Future<void> deletePlaylist(String playlistId) {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = await playlistRepository.getById(normalizedPlaylistId);

      if (playlist == null) {
        throw StateError('Playlist not found: $normalizedPlaylistId');
      }

      await playlistRepository.delete(normalizedPlaylistId);
    });
  }

  Future<PlaylistItem> addSong({
    required String playlistId,
    required String songId,
    DateTime? now,
  }) {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    final normalizedSongId = _requiredId(songId, 'songId', 'Song id');

    final timestamp = now ?? _now();

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = await playlistRepository.getById(normalizedPlaylistId);

      if (playlist == null) {
        throw StateError('Playlist not found: $normalizedPlaylistId');
      }

      final song = await context.songRepository.getById(normalizedSongId);

      if (song == null) {
        throw StateError('Song not found: $normalizedSongId');
      }

      final items = await playlistRepository.getItems(normalizedPlaylistId);

      for (final item in items) {
        if (item.songId == normalizedSongId) {
          return item;
        }
      }

      var nextPosition = 0;

      for (final item in items) {
        if (item.position >= nextPosition) {
          nextPosition = item.position + 1;
        }
      }

      final item = PlaylistItem(
        id: _generatePlaylistItemId(),
        playlistId: normalizedPlaylistId,
        songId: normalizedSongId,
        position: nextPosition,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      await playlistRepository.addItem(item);

      await playlistRepository.save(playlist.copyWith(updatedAt: timestamp));

      return item;
    });
  }

  Future<bool> removeSong({
    required String playlistId,
    required String songId,
    DateTime? now,
  }) {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    final normalizedSongId = _requiredId(songId, 'songId', 'Song id');

    final timestamp = now ?? _now();

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = await playlistRepository.getById(normalizedPlaylistId);

      if (playlist == null) {
        throw StateError('Playlist not found: $normalizedPlaylistId');
      }

      final items = await playlistRepository.getItems(normalizedPlaylistId);

      PlaylistItem? target;

      for (final item in items) {
        if (item.songId == normalizedSongId) {
          target = item;
          break;
        }
      }

      if (target == null) {
        return false;
      }

      await playlistRepository.removeItem(target.id);

      final remaining = [
        for (final item in items)
          if (item.id != target.id) item,
      ];

      for (var index = 0; index < remaining.length; index++) {
        final item = remaining[index];

        if (item.position == index) {
          continue;
        }

        await playlistRepository.saveItem(
          item.copyWith(position: index, updatedAt: timestamp),
        );
      }

      await playlistRepository.save(playlist.copyWith(updatedAt: timestamp));

      return true;
    });
  }

  Future<List<PlaylistItem>> reorderItems({
    required String playlistId,
    required List<String> orderedItemIds,
    DateTime? now,
  }) {
    final normalizedPlaylistId = _requiredId(
      playlistId,
      'playlistId',
      'Playlist id',
    );

    final normalizedItemIds = [
      for (final itemId in orderedItemIds)
        _requiredId(itemId, 'orderedItemIds', 'Playlist item id'),
    ];

    if (normalizedItemIds.toSet().length != normalizedItemIds.length) {
      throw ArgumentError.value(
        orderedItemIds,
        'orderedItemIds',
        'Playlist item ids must not contain duplicates.',
      );
    }

    final timestamp = now ?? _now();

    return mutationRunner.run((context) async {
      final playlistRepository = _requirePlaylistRepository(context);

      final playlist = await playlistRepository.getById(normalizedPlaylistId);

      if (playlist == null) {
        throw StateError('Playlist not found: $normalizedPlaylistId');
      }

      final items = await playlistRepository.getItems(normalizedPlaylistId);

      final existingById = {for (final item in items) item.id: item};

      if (existingById.length != normalizedItemIds.length ||
          !existingById.keys.toSet().containsAll(normalizedItemIds)) {
        throw ArgumentError.value(
          orderedItemIds,
          'orderedItemIds',
          'Reorder must contain every playlist item exactly once.',
        );
      }

      var changed = false;
      final reordered = <PlaylistItem>[];

      for (var index = 0; index < normalizedItemIds.length; index++) {
        final item = existingById[normalizedItemIds[index]]!;

        if (item.position == index) {
          reordered.add(item);
          continue;
        }

        changed = true;

        final updated = item.copyWith(position: index, updatedAt: timestamp);

        await playlistRepository.saveItem(updated);
        reordered.add(updated);
      }

      if (changed) {
        await playlistRepository.save(playlist.copyWith(updatedAt: timestamp));
      }

      return List<PlaylistItem>.unmodifiable(reordered);
    });
  }

  static bool _hasAvailableMedia(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  PlaylistRepository _requirePlaylistRepository(SyncMutationContext context) {
    final playlistRepository = context.playlistRepository;

    if (playlistRepository == null) {
      throw StateError(
        'Playlist repository is not available in the mutation context.',
      );
    }

    return playlistRepository;
  }

  String _requiredName(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'name',
        'Playlist name must not be blank.',
      );
    }

    return trimmed;
  }

  String _requiredId(String value, String argumentName, String label) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        argumentName,
        '$label must not be blank.',
      );
    }

    return trimmed;
  }
}
