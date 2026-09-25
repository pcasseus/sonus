import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/domain/models/lyric_line.dart';
import 'package:sonus_next/features/player/domain/models/track_lyrics.dart';

void main() {
  test('reports empty lyrics when no content exists', () {
    const lyrics = TrackLyrics(songId: 'song_1');

    expect(lyrics.hasLyrics, isFalse);
    expect(lyrics.hasPlainLyrics, isFalse);
    expect(lyrics.hasSyncedLyrics, isFalse);
  });

  test('reports plain lyrics independently of synced lyrics', () {
    const lyrics = TrackLyrics(
      songId: 'song_1',
      plainText: 'First line\nSecond line',
    );

    expect(lyrics.hasLyrics, isTrue);
    expect(lyrics.hasPlainLyrics, isTrue);
    expect(lyrics.hasSyncedLyrics, isFalse);
  });

  test('finds active synced line from playback position', () {
    const first = LyricLine(timestamp: Duration(seconds: 5), text: 'First');
    const second = LyricLine(timestamp: Duration(seconds: 10), text: 'Second');
    const third = LyricLine(timestamp: Duration(seconds: 15), text: 'Third');

    const lyrics = TrackLyrics(
      songId: 'song_1',
      syncedLines: <LyricLine>[first, second, third],
    );

    expect(lyrics.hasSyncedLyrics, isTrue);
    expect(lyrics.activeLineAt(const Duration(seconds: 4)), isNull);
    expect(lyrics.activeLineAt(const Duration(seconds: 5)), first);
    expect(lyrics.activeLineAt(const Duration(seconds: 12)), second);
    expect(lyrics.activeLineAt(const Duration(seconds: 30)), third);
  });
}
