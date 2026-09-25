import '../../domain/models/track_lyrics.dart';

enum LyricsStatus { idle, loading, loaded, empty, failed }

class LyricsState {
  const LyricsState({
    this.songId,
    this.status = LyricsStatus.idle,
    this.lyrics,
    this.error,
  });

  final String? songId;
  final LyricsStatus status;
  final TrackLyrics? lyrics;
  final Object? error;

  bool get isLoading => status == LyricsStatus.loading;
  bool get hasLyrics => lyrics?.hasLyrics ?? false;
  bool get hasError => status == LyricsStatus.failed;
}
