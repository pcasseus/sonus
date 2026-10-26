enum ChartMomentEventType {
  // Rank state.
  rankRise,
  rankFall,
  rankSame,

  // Chart lifecycle.
  debut,
  reentry,
  chartExit,

  // Peak behavior.
  newPeak,
  peakMatch,

  // Tier behavior.
  firstThresholdEntry,
  thresholdReturn,
  thresholdExit,

  // Number-one behavior.
  firstNumberOne,
  returnToNumberOne,
  losesNumberOne,

  // Longevity.
  consecutiveWeeksMilestone,
  totalWeeksMilestone,
  consecutiveThresholdWeeksMilestone,
  totalThresholdWeeksMilestone,

  // Listening milestones.
  lifetimeStreamMilestone,

  // Artist/catalog accomplishments.
  artistFirstThresholdSong,
  artistFirstThresholdAlbum,
  artistNthThresholdSong,
  artistNthThresholdAlbum,
  artistHighestChartingSong,
  artistHighestChartingAlbum,
  artistFirstNumberOneSong,
  artistFirstNumberOneAlbum,
  artistNthNumberOneSong,
  artistNthNumberOneAlbum,

  // Rich artist/catalog accomplishments.
  artistReturnsToNumberOneSong,
  artistReturnsToNumberOneAlbum,
  artistSimultaneousThresholdSongs,
  artistSimultaneousThresholdAlbums,

  // Artist ranking (SN-45): from the same qualified plays, with each play
  // counted once for the artist it is attributed to.

  /// The artist becomes the most-streamed artist, passing the previous
  /// leader (the related entity).
  artistBecomesTopArtist,

  /// The artist's qualified plays reach a milestone.
  artistStreamMilestone,
}
