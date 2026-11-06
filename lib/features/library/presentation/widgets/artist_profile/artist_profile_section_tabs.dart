import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';

/// One destination of [ArtistProfileSectionTabs]: a real section of the
/// page, found by its [anchor].
class ArtistProfileSectionTab {
  const ArtistProfileSectionTab({required this.label, required this.anchor});

  final String label;
  final GlobalKey anchor;
}

/// Lightweight section navigation for the Artist Profile (Profile Lab):
/// text tabs with an accent underline under the selected one and a hairline
/// under the row, subordinate to Play all. Each tab scrolls to its real
/// section; [selected] follows the scroll position (see the page). Scrolls
/// sideways when the labels do not fit (large text).
class ArtistProfileSectionTabs extends StatelessWidget {
  const ArtistProfileSectionTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.accent,
  });

  final List<ArtistProfileSectionTab> tabs;
  final ValueNotifier<int> selected;
  final ValueChanged<int> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey<String>('artist-profile-section-tabs'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, current, _) => Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Semantics(
                  button: true,
                  selected: i == current,
                  label: tabs[i].label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey<String>('artist-profile-section-tab-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(i),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: EdgeInsets.fromLTRB(i == 0 ? 2 : 12, 0, 12, 0),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tabs[i].label,
                            maxLines: 1,
                            softWrap: false,
                            style: text.titleSmall?.copyWith(
                              color: i == current
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              fontWeight: i == current
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: tokens.motion.short,
                            height: 3,
                            width: i == current ? 28 : 0,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
