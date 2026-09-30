import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/playlists/data/mappers/playlist_item_row_mapper.dart';
import 'package:sonus_next/features/playlists/data/mappers/playlist_row_mapper.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist.dart';
import 'package:sonus_next/features/playlists/domain/entities/playlist_item.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 29, 12);
  final updatedAt = DateTime.utc(2026, 9, 29, 13);

  test('playlist round trips through SQLite row mapper', () {
    final playlist = Playlist(
      id: 'playlist_1',
      name: 'Favorites',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = PlaylistRowMapper.toRow(playlist);
    final restored = PlaylistRowMapper.fromRow(row);

    expect(restored, playlist);
    expect(restored.name, 'Favorites');
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
  });

  test('playlist item round trips through SQLite row mapper', () {
    final item = PlaylistItem(
      id: 'playlist_item_1',
      playlistId: 'playlist_1',
      songId: 'song_1',
      position: 4,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final row = PlaylistItemRowMapper.toRow(item);
    final restored = PlaylistItemRowMapper.fromRow(row);

    expect(restored, item);
    expect(restored.playlistId, 'playlist_1');
    expect(restored.songId, 'song_1');
    expect(restored.position, 4);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
  });
}
