enum AppDestination {
  home('Home'),
  hot100('Hot 100'),
  tracks('Tracks'),
  library('Library'),
  settings('Settings');

  const AppDestination(this.label);

  final String label;
}
