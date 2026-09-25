import 'lyric_line.dart';

class TrackLyrics {
  const TrackLyrics({
    required this.songId,
    this.plainText,
    this.syncedLines = const <LyricLine>[],
  });

  final String songId;
  final String? plainText;
  final List<LyricLine> syncedLines;

  bool get hasPlainLyrics => plainText?.trim().isNotEmpty ?? false;

  bool get hasSyncedLyrics => syncedLines.isNotEmpty;

  bool get hasLyrics => hasPlainLyrics || hasSyncedLyrics;

  LyricLine? activeLineAt(Duration position) {
    LyricLine? activeLine;

    for (final line in syncedLines) {
      if (line.timestamp > position) {
        break;
      }
      activeLine = line;
    }

    return activeLine;
  }
}
