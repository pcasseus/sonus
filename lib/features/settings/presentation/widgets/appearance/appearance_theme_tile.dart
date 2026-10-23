import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/sonus_theme_catalog.dart';
import '../../../../../core/design/sonus_theme_factory.dart';
import '../../../../../core/design/sonus_theme_id.dart';
import '../../../../../core/design/widgets/sonus_decorations.dart';

/// A selectable swatch of one theme, drawn in that theme's own colours.
///
/// The selected tile is marked with a check icon as well as a heavier
/// border, so selection never depends on colour alone.
class AppearanceThemeTile extends StatelessWidget {
  const AppearanceThemeTile({
    super.key,
    required this.themeId,
    required this.baseSpec,
    required this.selected,
    required this.onSelected,
  });

  final SonusThemeId themeId;

  /// The active spec; the tile swaps in [themeId] so typography, decoration
  /// and accessibility settings show as they would apply.
  final SonusAppearanceSpec baseSpec;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SonusThemeFactory.build(baseSpec.copyWith(themeId: themeId)),
      child: _ThemeTileBody(
        themeId: themeId,
        selected: selected,
        onSelected: onSelected,
      ),
    );
  }
}

class _ThemeTileBody extends StatelessWidget {
  const _ThemeTileBody({
    required this.themeId,
    required this.selected,
    required this.onSelected,
  });

  final SonusThemeId themeId;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    return Semantics(
      key: ValueKey<String>('appearance-theme-${themeId.storageKey}'),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${themeId.label} theme',
      hint: SonusThemeCatalog.of(themeId).identity,
      onTap: onSelected,
      excludeSemantics: true,
      child: Material(
        color: colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? colors.focus : colors.border,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: EdgeInsets.all(tokens.metrics.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _Swatch(color: colors.accentPrimary),
                    _Swatch(color: colors.accentSecondary),
                    _Swatch(color: colors.surface, outline: colors.border),
                    const Spacer(),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: colors.focus,
                      ),
                  ],
                ),
                SizedBox(height: tokens.metrics.spaceSm),
                const SonusMotifMark(width: 44, height: 8),
                SizedBox(height: tokens.metrics.spaceSm),
                Text(
                  themeId.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.outline});

  final Color color;
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: outline == null ? null : Border.all(color: outline!),
        ),
        child: const SizedBox.square(dimension: 16),
      ),
    );
  }
}
