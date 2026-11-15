import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/charts/presentation/models/moment_related_songs.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

/// App Update 1.3 (REF-1.3-03): a Moment story's Related row never
/// suggests the story's own recording; album first, then primary artist,
/// else nothing.
LibraryTrack _t(
  String id, {
  String? title,
  String artist = 'artist_a',
  String album = 'album_1',
  String edition = 'ed_std',
  int track = 1,
  int disc = 1,
  bool available = true,
  bool blocked = false,
  String? file,
  String? versionLabel,
  List<SongVersionCharacteristic> characteristics = const [],
  List<String> coPrimary = const [],
}) => LibraryTrack(
  songId: id,
  title: title ?? 'Song $id',
  artistId: artist,
  artistName: 'Artist $artist',
  albumId: album,
  albumTitle: 'Album $album',
  albumEditionId: edition,
  albumEditionTitle: 'Edition $edition',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: track,
  discNumber: disc,
  durationSeconds: 200,
  isSingle: false,
  featuredArtists: const [],
  coPrimaryArtists: coPrimary,
  versionLabel: versionLabel,
  versionCharacteristics: characteristics,
  dateAdded: DateTime.utc(2026),
  isAvailable: available,
  isSongBlocked: blocked,
  filePath: file ?? '/music/$id.mp3',
);

List<String> _ids(List<LibraryTrack> tracks) => [
  for (final t in tracks) t.songId,
];

void main() {
  test('never suggests the current song, and prefers its album in track '
      'order', () {
    final current = _t('s2', track: 2);
    final library = [
      _t('s3', track: 3),
      current,
      _t('s1', track: 1),
      _t('x1', album: 'album_2'),
    ];
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: library,
    );
    expect(_ids(chosen), ['s1', 's3']);
    expect(_ids(chosen), isNot(contains('s2')));
  });

  test('songs on the relevant edition come before the album\'s other '
      'songs', () {
    final current = _t('s1', edition: 'ed_std');
    final deluxeOnly = _t('d1', edition: 'ed_dlx', track: 1);
    final standard = _t('s9', edition: 'ed_std', track: 9);
    final memberships = {
      's1': {'ed_std', 'ed_dlx'},
      'd1': {'ed_dlx'},
      's9': {'ed_std', 'ed_dlx'},
    };
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [current, deluxeOnly, standard],
      editionsOf: (id) => memberships[id] ?? const {},
    );
    // Both share an edition with s1 (the Deluxe lists all three), so
    // track order decides.
    expect(_ids(chosen), ['d1', 's9']);

    final onlyStandard = MomentRelatedSongs.select(
      current: current,
      library: [current, deluxeOnly, standard],
      editionsOf: (id) => id == 's1' ? {'ed_std'} : memberships[id]!,
    );
    expect(_ids(onlyStandard), ['s9', 'd1']);
  });

  test('another edition placement of the same recording is never '
      'suggested', () {
    final current = _t('s1', title: 'Skyline', edition: 'ed_std');
    // The same recording imported again on the Deluxe (a duplicate song
    // row), the same file under another id, and a different version.
    final duplicate = _t('s1_dup', title: 'skyline', edition: 'ed_dlx');
    final sameFile = _t('s1_file', title: 'Other', file: '/music/s1.mp3');
    final remix = _t(
      's1_remix',
      title: 'Skyline',
      characteristics: const [SongVersionCharacteristic.remix],
      track: 2,
    );
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [current, duplicate, sameFile, remix],
    );
    expect(_ids(chosen), ['s1_remix']);
  });

  test('two songs that are one recording are suggested once', () {
    final current = _t('s1');
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [
        current,
        _t('a', title: 'Echo', track: 2),
        _t('b', title: 'ECHO', track: 3, edition: 'ed_dlx'),
      ],
    );
    expect(_ids(chosen), ['a']);
  });

  test('unavailable and blocked songs are never suggested', () {
    final current = _t('s1');
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [
        current,
        _t('gone', available: false, track: 2),
        _t('hidden', blocked: true, track: 3),
        _t('nofile', file: ' ', track: 4),
        _t('ok', track: 5),
      ],
    );
    expect(_ids(chosen), ['ok']);
  });

  test('a one-song album or standalone single falls back to the primary '
      'artist, ranked first', () {
    final single = _t('single', album: 'single_album', edition: 'ed_single');
    final library = [
      single,
      _t('b', title: 'Beta', album: 'album_2'),
      _t('a', title: 'Alpha', album: 'album_3'),
      _t('r', title: 'Zed', album: 'album_2', track: 4),
      _t('other', artist: 'artist_b', album: 'album_9'),
    ];
    final chosen = MomentRelatedSongs.select(
      current: single,
      library: library,
      allTimeRankOf: (id) => id == 'r' ? 4 : null,
    );
    // Ranked first, then by title; another artist's song never.
    expect(_ids(chosen), ['r', 'a', 'b']);
  });

  test('the artist tier uses the primary artist, not co-credits', () {
    final current = _t('s1', album: 'solo');
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [
        current,
        // artist_a is only co-primary here: not the primary artist.
        _t('duet', artist: 'artist_b', album: 'duets', coPrimary: ['A']),
        _t('own', album: 'second'),
      ],
    );
    expect(_ids(chosen), ['own']);
  });

  test('the album tier wins over the artist tier entirely', () {
    final current = _t('s1');
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [
        current,
        _t('s2', track: 2),
        _t('other', album: 'album_2'),
      ],
    );
    expect(_ids(chosen), ['s2']);
  });

  test('nothing qualifies: no suggestions', () {
    final current = _t('only', album: 'single_album');
    expect(
      MomentRelatedSongs.select(
        current: current,
        library: [
          current,
          _t('x', artist: 'artist_b', album: 'z'),
        ],
      ),
      isEmpty,
    );
  });

  test('at most the limit, with no duplicate identities', () {
    final current = _t('s0');
    final chosen = MomentRelatedSongs.select(
      current: current,
      library: [
        current,
        for (var i = 1; i < 9; i++) _t('s$i', track: i),
      ],
    );
    expect(_ids(chosen), ['s1', 's2', 's3']);
    expect(_ids(chosen).toSet(), hasLength(3));
  });
}
