import 'package:flutter/material.dart';

import '../../../../core/design/sonus_cinematic_colors.dart';

/// How the Library shows its artists.
enum LibraryView {
  /// The fighting-game Artist Roster (default).
  roster('Artist Roster', Icons.sports_esports_rounded),

  /// The cinematic Film Reel.
  filmReel('Film Reel', Icons.view_carousel_rounded);

  const LibraryView(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The stored name of [this], for preferences.
  String get storageName => name;

  /// The view stored as [stored]; the Roster for anything else.
  static LibraryView fromStorage(String? stored) {
    for (final view in values) {
      if (view.name == stored) return view;
    }
    return roster;
  }
}

/// The switch between the Library's two views, in both views' headers: a
/// pill with one button per view, the current one lit.
class LibraryViewSwitch extends StatelessWidget {
  const LibraryViewSwitch({
    super.key,
    required this.current,
    required this.onChanged,
    required this.colors,
  });

  final LibraryView current;
  final ValueChanged<LibraryView> onChanged;
  final SonusCinematicColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.edge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final view in LibraryView.values)
              Semantics(
                selected: view == current,
                button: true,
                label: '${view.label} view',
                excludeSemantics: true,
                child: IconButton(
                  key: ValueKey<String>(
                    view == LibraryView.roster
                        ? 'library-view-roster'
                        : 'library-view-reel',
                  ),
                  tooltip: view.label,
                  isSelected: view == current,
                  onPressed: view == current ? () {} : () => onChanged(view),
                  style: IconButton.styleFrom(
                    backgroundColor: view == current
                        ? colors.accent
                        : Colors.transparent,
                    foregroundColor: view == current
                        ? colors.onAccent
                        : colors.textPrimary,
                  ),
                  icon: Icon(view.icon),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
