import 'package:flutter/material.dart';

import '../sonus_theme.dart';

/// A numeric column of a [SonusNumericTable].
@immutable
class SonusTableColumn {
  const SonusTableColumn({required this.label, this.width = 96});

  /// Short header text, e.g. "STREAMS".
  final String label;

  /// Width at 1x text; it grows with the text scale.
  final double width;
}

/// One row of a [SonusNumericTable].
@immutable
class SonusTableRow {
  const SonusTableRow({
    required this.key,
    required this.identity,
    required this.cells,
    required this.spokenLabel,
    this.onTap,
  });

  /// Identifies the row in tests and to the framework.
  final Key key;

  /// The frozen identifying content: rank, artwork and title.
  final Widget identity;

  /// One value per column, already formatted.
  final List<Widget> cells;

  /// What a screen reader announces for the whole row.
  final String spokenLabel;
  final VoidCallback? onTap;
}

/// A spreadsheet-style table whose identifying column stays fixed while the
/// numeric columns scroll sideways.
///
/// On narrow screens or with large text every row becomes a stacked card,
/// so nothing depends on horizontal scrolling.
///
/// The scrolling part has its own PageStorage slot ([storageId]). Without
/// it the table would share the page's slot and reopen at the page's
/// vertical offset, hiding its leftmost columns.
class SonusNumericTable extends StatelessWidget {
  const SonusNumericTable({
    super.key,
    required this.storageId,
    required this.identityLabel,
    required this.columns,
    required this.rows,
    this.identityWidth = 220,
    this.rowHeight = 64,
  });

  /// Width below which, at 1x text, the table stacks its rows. Normal
  /// phones (360dp and up) keep the frozen column; 320dp screens stack.
  static const double stackedBelowWidth = 300;

  /// Largest share of the table the frozen identity column may take, so
  /// some numeric columns always show beside it on narrow phones.
  static const double maxIdentityShare = 0.55;

  /// Text scale above which the table stacks its rows.
  static const double stackedAboveTextScale = 1.3;

  final String storageId;
  final String identityLabel;
  final double identityWidth;

  /// Row height at 1x text; it grows with the text scale. Raise it when the
  /// identity cell shows a third line, such as a status badge.
  final double rowHeight;
  final List<SonusTableColumn> columns;
  final List<SonusTableRow> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stacked =
            constraints.maxWidth < stackedBelowWidth ||
            textScale > stackedAboveTextScale;

        return stacked
            ? _StackedTable(table: this)
            : _FrozenTable(
                table: this,
                textScale: textScale,
                identityWidth: identityWidth.clamp(
                  0,
                  constraints.maxWidth * maxIdentityShare,
                ),
              );
      },
    );
  }
}

class _FrozenTable extends StatelessWidget {
  const _FrozenTable({
    required this.table,
    required this.textScale,
    required this.identityWidth,
  });

  final SonusNumericTable table;
  final double textScale;
  final double identityWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final headerHeight = 40 * textScale;
    final rowHeight = table.rowHeight * textScale;

    Color rowColor(int index) => index.isEven
        ? colors.surface
        : Color.lerp(colors.surface, colors.raisedSurface, 0.6)!;

    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: colors.divider),
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Frozen identity column.
            SizedBox(
              width: identityWidth,
              child: Column(
                children: [
                  _HeaderCell(
                    height: headerHeight,
                    color: colors.raisedSurface,
                    alignment: Alignment.centerLeft,
                    child: ExcludeSemantics(
                      child: Text(table.identityLabel, style: headerStyle),
                    ),
                  ),
                  for (final (index, row) in table.rows.indexed)
                    Semantics(
                      key: row.key,
                      container: true,
                      button: row.onTap != null,
                      label: row.spokenLabel,
                      excludeSemantics: true,
                      child: Material(
                        color: rowColor(index),
                        child: InkWell(
                          onTap: row.onTap,
                          child: SizedBox(
                            height: rowHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: row.identity,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Scrolling numeric columns, read through the identity cell.
            Expanded(
              child: ExcludeSemantics(
                child: SingleChildScrollView(
                  key: PageStorageKey<String>('sonus-table-${table.storageId}'),
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final column in table.columns)
                            _HeaderCell(
                              width: column.width * textScale,
                              height: headerHeight,
                              color: colors.raisedSurface,
                              alignment: Alignment.centerRight,
                              child: Text(column.label, style: headerStyle),
                            ),
                        ],
                      ),
                      for (final (index, row) in table.rows.indexed)
                        Material(
                          color: rowColor(index),
                          child: InkWell(
                            onTap: row.onTap,
                            child: SizedBox(
                              height: rowHeight,
                              child: Row(
                                children: [
                                  for (final (cellIndex, cell)
                                      in row.cells.indexed)
                                    SizedBox(
                                      width:
                                          table.columns[cellIndex].width *
                                          textScale,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: cell,
                                        ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.height,
    required this.color,
    required this.alignment,
    required this.child,
    this.width,
  });

  final double? width;
  final double height;
  final Color color;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: alignment,
      child: child,
    );
  }
}

/// Each row as a card: identity on top, then "LABEL value" pairs that wrap.
class _StackedTable extends StatelessWidget {
  const _StackedTable({required this.table});

  final SonusNumericTable table;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in table.rows)
          Padding(
            key: row.key,
            padding: EdgeInsets.only(bottom: tokens.metrics.spaceSm),
            child: Semantics(
              container: true,
              button: row.onTap != null,
              label: row.spokenLabel,
              excludeSemantics: true,
              child: Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    tokens.metrics.cardRadius,
                  ),
                  side: BorderSide(color: colors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: row.onTap,
                  child: Padding(
                    padding: EdgeInsets.all(tokens.metrics.spaceMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        row.identity,
                        SizedBox(height: tokens.metrics.spaceSm),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            for (final (index, cell) in row.cells.indexed)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    table.columns[index].label,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  cell,
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
