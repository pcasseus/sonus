/// Which calendar week a Home ranking section shows.
///
/// Early in a week there is too little listening for a meaningful ranking,
/// so a section shows last week's completed ranking, labelled as such,
/// until this week has enough entries of its own.
enum HomeRankingWeek { thisWeek, lastWeek }
