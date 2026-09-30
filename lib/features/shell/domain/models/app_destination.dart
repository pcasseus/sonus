enum AppDestination {
  home('Home'),
  hot100('Hot 100'),
  tracks('Tracks'),
  library('Library'),
  playlists('Playlists'),
  settings('Settings');

  const AppDestination(this.label);

  final String label;
}
