import 'dart:math' as math;

class ListeningQualificationPolicy {
  const ListeningQualificationPolicy();

  static const Duration standardThreshold = Duration(seconds: 30);
  static const Duration shortTrackMinimum = Duration(seconds: 5);

  Duration thresholdFor(Duration trackDuration) {
    if (trackDuration <= Duration.zero) {
      return standardThreshold;
    }

    if (trackDuration >= standardThreshold) {
      return standardThreshold;
    }

    final halfDurationMilliseconds = (trackDuration.inMilliseconds / 2).ceil();

    final shortTrackThresholdMilliseconds = math.max(
      shortTrackMinimum.inMilliseconds,
      halfDurationMilliseconds,
    );

    return Duration(
      milliseconds: math.min(
        trackDuration.inMilliseconds,
        shortTrackThresholdMilliseconds,
      ),
    );
  }

  bool qualifies({
    required Duration listenedDuration,
    required Duration trackDuration,
  }) {
    if (listenedDuration.isNegative) {
      return false;
    }

    return listenedDuration >= thresholdFor(trackDuration);
  }
}
