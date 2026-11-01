import 'package:flutter/material.dart';

import '../../library/application/models/library_track.dart';
import 'song_stats_page.dart';

/// Opens the one Song Stats page for [songId] (Charts 2.0 C4). Every entry
/// point — chart rows and the song menus — comes through here.
///
/// [playContext] is the list Play starts from (the chart, the album, the
/// playlist); the song alone when null.
Future<void> openSongStats(
  BuildContext context, {
  required String songId,
  String? initialTitle,
  List<LibraryTrack>? playContext,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: SongStatsPage.routeName),
      builder: (_) => SongStatsPage(
        songId: songId,
        initialTitle: initialTitle,
        playContext: playContext,
      ),
    ),
  );
}

/// The "View Stats" entry for a song's options menu.
PopupMenuItem<T> songStatsMenuItem<T>(T value, {Key? key}) {
  return PopupMenuItem<T>(
    key: key,
    value: value,
    child: const ListTile(
      leading: Icon(Icons.insights_rounded),
      title: Text('View Stats'),
      contentPadding: EdgeInsets.zero,
    ),
  );
}
