import 'package:flutter/material.dart';

import '../../../library/application/models/library_track.dart';
import '../widgets/settings/settings_section.dart';

/// A read-only list of songs whose audio file is not available on this
/// device. Nothing here relinks, rescans or removes songs.
class UnavailableSongsPage extends StatelessWidget {
  const UnavailableSongsPage({super.key, required this.songs});

  final List<LibraryTrack> songs;

  @override
  Widget build(BuildContext context) {
    // The explanation and heading come first; songs are built lazily so a
    // large missing folder stays fast.
    const leadingItems = 2;

    return Scaffold(
      key: const ValueKey<String>('unavailable-songs-page'),
      appBar: AppBar(title: const Text('Unavailable songs')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: leadingItems + songs.length,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const _Explanation();
          }

          if (index == 1) {
            return songs.isEmpty
                ? const Card(
                    key: ValueKey<String>('unavailable-songs-empty'),
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline_rounded),
                      title: Text('Every song can be played on this device.'),
                    ),
                  )
                : Padding(
                    key: const ValueKey<String>('unavailable-songs-count'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Semantics(
                      header: true,
                      child: Text(
                        songs.length == 1
                            ? '1 unavailable song'
                            : '${songs.length} unavailable songs',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  );
          }

          final song = songs[index - leadingItems];

          return ListTile(
            key: ValueKey<String>('unavailable-song-${song.songId}'),
            leading: const Icon(Icons.music_off_rounded),
            title: Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${song.artistName} · ${song.albumTitle}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation();

  @override
  Widget build(BuildContext context) {
    return const SettingsSection(
      title: 'Why songs become unavailable',
      children: [
        SettingsInfoTile(
          icon: Icons.folder_off_outlined,
          title: 'The audio file was moved or deleted',
          body:
              'Sonus keeps the song, its history and its metadata. It just '
              'cannot play it on this device.',
        ),
        SettingsInfoTile(
          icon: Icons.manage_search_rounded,
          title: 'Getting them back',
          body:
              'Put the files back in your music folder and use "Scan for '
              'changes" in Import music. After a restore, link your music '
              'from Backup & Restore.',
        ),
      ],
    );
  }
}
