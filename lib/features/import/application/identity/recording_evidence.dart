import 'package:sonus_next/core/identity/text_normalizer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

/// Decides whether a file whose artist, title, version and album match an
/// existing song is nevertheless a different recording.
///
/// Conservative in both directions: only concrete evidence separates two
/// recordings, so a genuine copy never becomes a second song, and a
/// different recording is never silently absorbed into the first.
class RecordingEvidence {
  const RecordingEvidence._();

  /// Durations closer than this are treated as the same recording; encoders
  /// and tag readers commonly disagree by a second or two.
  static const int durationToleranceSeconds = 3;

  /// For long tracks, a relative tolerance applies when it is larger.
  static const double durationToleranceRatio = 0.02;

  /// True when [metadata] is evidently a different recording than [song]:
  /// both durations are known and differ beyond the tolerance, or the
  /// featured artists differ. An unknown duration is not evidence.
  static bool distinguishes(Song song, AudioMetadata metadata) {
    return _durationsDiffer(song.durationSeconds, metadata.durationSeconds) ||
        !_sameFeatures(song.featuredArtists, metadata.featuredArtists);
  }

  static bool _durationsDiffer(int a, int b) {
    if (a <= 0 || b <= 0) {
      return false;
    }

    final longer = a > b ? a : b;
    final relative = (longer * durationToleranceRatio).round();
    final tolerance = relative > durationToleranceSeconds
        ? relative
        : durationToleranceSeconds;

    return (a - b).abs() > tolerance;
  }

  static bool _sameFeatures(List<String> a, List<String> b) {
    Set<String> canonical(List<String> names) => {
      for (final name in names)
        if (TextNormalizer.canonicalize(name).isNotEmpty)
          TextNormalizer.canonicalize(name),
    };

    final left = canonical(a);
    final right = canonical(b);

    return left.length == right.length && left.containsAll(right);
  }
}
