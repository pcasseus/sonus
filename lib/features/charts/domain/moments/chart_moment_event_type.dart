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
}
