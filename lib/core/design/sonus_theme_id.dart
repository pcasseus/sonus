/// The nine Sonus visual themes.
///
/// [storageKey] is the persisted identity of a theme. It must never change
/// once released, because saved preferences, and later backups and cloud
/// sync, refer to it.
enum SonusThemeId {
  concreteSpray('concrete_spray', 'Concrete & Spray'),
  kickflip('kickflip', 'Kickflip'),
  afterHours('after_hours', 'After Hours'),
  y2kReplay('y2k_replay', 'Y2K Replay'),
  neonMixtape('neon_mixtape', 'Neon Mixtape'),
  haze2017('haze_2017', '2017 Haze'),
  monochrome('monochrome', 'Monochrome'),
  daylight('daylight', 'Daylight'),
  evergreen('evergreen', 'Evergreen');

  const SonusThemeId(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static const SonusThemeId defaultTheme = concreteSpray;

  /// The theme stored under [key], or null for an unknown or missing key.
  static SonusThemeId? fromStorageKey(Object? key) {
    for (final id in values) {
      if (id.storageKey == key) {
        return id;
      }
    }

    return null;
  }
}
