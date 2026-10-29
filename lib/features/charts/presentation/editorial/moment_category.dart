import 'moment_family.dart';

/// What a Moments story is about, for filtering the feed (SN-50 F-Q25).
/// Every family belongs to exactly one.
enum MomentCategory {
  numberOnes('Number ones'),
  entries('Debuts and re-entries'),
  peaks('Peaks and climbs'),
  milestones('Milestones'),
  artists('Artist records');

  const MomentCategory(this.label);

  final String label;

  static MomentCategory of(MomentFamily family) => switch (family) {
    MomentFamily.songDebutNumberOne ||
    MomentFamily.songFirstNumberOne ||
    MomentFamily.songReturnsToNumberOne ||
    MomentFamily.songSelfReplacement ||
    MomentFamily.releaseDebutNumberOne ||
    MomentFamily.releaseReachesNumberOne ||
    MomentFamily.releaseReturnsToNumberOne ||
    MomentFamily.releaseSelfReplacement ||
    MomentFamily.artistFirstNumberOne ||
    MomentFamily.artistNthNumberOne ||
    MomentFamily.artistRepeatNumberOne ||
    MomentFamily.artistFirstNumberOneRelease ||
    MomentFamily.artistNthNumberOneRelease ||
    MomentFamily.artistRepeatNumberOneRelease => numberOnes,
    MomentFamily.songDebutTop10 ||
    MomentFamily.songDebut ||
    MomentFamily.songBubblingUnderDebut ||
    MomentFamily.songReentry ||
    MomentFamily.releaseDebut ||
    MomentFamily.releaseReentry => entries,
    MomentFamily.songHot100Breakthrough ||
    MomentFamily.songNewPeak ||
    MomentFamily.songPeakMatch ||
    MomentFamily.songBigClimb ||
    MomentFamily.songBiggestGainer ||
    MomentFamily.songFirstThreshold ||
    MomentFamily.songThresholds ||
    MomentFamily.releaseNewPeak ||
    MomentFamily.releaseFirstThreshold ||
    MomentFamily.releaseThresholds => peaks,
    MomentFamily.songStreamMilestone ||
    MomentFamily.songWeeksMilestone ||
    MomentFamily.releaseStreamMilestone ||
    MomentFamily.releaseWeeksMilestone ||
    MomentFamily.artistStreamMilestone => milestones,
    MomentFamily.artistFirstHot100 ||
    MomentFamily.artistFirstTop10 ||
    MomentFamily.artistNthTop10 ||
    MomentFamily.artistTopArtist ||
    MomentFamily.artistSimultaneous ||
    MomentFamily.artistSimultaneousReleases => artists,
  };
}
