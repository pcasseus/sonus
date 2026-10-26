import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../domain/entities/release_date.dart';

/// What the release date editor returned: a new date, or clearing it.
sealed class ReleaseDateEdit {
  const ReleaseDateEdit();
}

final class ReleaseDateSet extends ReleaseDateEdit {
  const ReleaseDateSet(this.date);

  final ReleaseDate date;
}

final class ReleaseDateCleared extends ReleaseDateEdit {
  const ReleaseDateCleared();
}

/// SN-49: sets a release date as precisely as it is known: a year
/// (`2026`), a month (`2026-04`) or a day (`2026-04-17`). It can be typed,
/// chosen on a calendar (which opens at the saved date and jumps between
/// years and decades from its year grid), or chosen as a month and year
/// without inventing a day.
///
/// Returns null when cancelled. A date less precise than [current] is only
/// returned after the user confirms that the extra detail will be removed.
Future<ReleaseDateEdit?> showReleaseDateEditor(
  BuildContext context, {
  required ReleaseDate? current,
  DateTime? today,
}) => showDialog<ReleaseDateEdit>(
  context: context,
  builder: (_) => ReleaseDateEditorDialog(current: current, today: today),
);

class ReleaseDateEditorDialog extends StatefulWidget {
  const ReleaseDateEditorDialog({super.key, required this.current, this.today});

  final ReleaseDate? current;

  /// Today, for the calendar's range; the clock when null.
  final DateTime? today;

  @override
  State<ReleaseDateEditorDialog> createState() =>
      _ReleaseDateEditorDialogState();
}

class _ReleaseDateEditorDialogState extends State<ReleaseDateEditorDialog> {
  static const int _firstYear = 1900;

  late final TextEditingController _text = TextEditingController(
    text: widget.current?.iso ?? '',
  );

  DateTime get _today => widget.today ?? DateTime.now();

  int get _lastYear => _today.year + 5;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _value => _text.text.trim();

  ReleaseDate? get _parsed {
    final date = ReleaseDate.tryParse(_value);
    if (date == null || date.year < _firstYear || date.year > _lastYear) {
      return null;
    }
    return date;
  }

  String? get _error {
    if (_value.isEmpty) return null;
    final date = ReleaseDate.tryParse(_value);
    if (date == null) {
      return 'Use 2026, 2026-04 or 2026-04-17, with a real month and day.';
    }
    if (date.year < _firstYear || date.year > _lastYear) {
      return 'Use a year from $_firstYear to $_lastYear.';
    }
    return null;
  }

  /// The calendar opens at the date being edited, or today.
  DateTime get _calendarStart {
    final date = _parsed ?? widget.current;
    if (date == null) return _today;
    final start = DateTime(date.year, date.month ?? 1, date.day ?? 1);
    final last = DateTime(_lastYear, 12, 31);
    return start.isAfter(last) ? last : start;
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _calendarStart,
      firstDate: DateTime(_firstYear),
      lastDate: DateTime(_lastYear, 12, 31),
      // Without a day to start from, open on the year grid so any year is
      // a scroll and a tap away.
      initialDatePickerMode: (_parsed ?? widget.current)?.day == null
          ? DatePickerMode.year
          : DatePickerMode.day,
      helpText: 'Release day',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _text.text = ReleaseDate.of(picked.year, picked.month, picked.day)!.iso;
    });
  }

  Future<void> _pickMonth() async {
    final start = _parsed ?? widget.current;
    final picked = await showDialog<ReleaseDate>(
      context: context,
      builder: (_) => _MonthYearDialog(
        initialYear: start?.year ?? _today.year,
        initialMonth: start?.month,
        firstYear: _firstYear,
        lastYear: _lastYear,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _text.text = picked.iso);
  }

  Future<void> _save() async {
    if (_value.isEmpty) {
      Navigator.of(context).pop(const ReleaseDateCleared());
      return;
    }
    final date = _parsed;
    if (date == null) return;

    final current = widget.current;
    final losesDetail =
        current != null &&
        date.precision.index < current.precision.index &&
        date != current;
    if (losesDetail && !await _confirmLessPrecise(current, date)) return;
    if (!mounted) return;
    Navigator.of(context).pop(ReleaseDateSet(date));
  }

  Future<bool> _confirmLessPrecise(
    ReleaseDate current,
    ReleaseDate next,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use a less exact date?'),
        content: Text(
          'The saved date is ${current.label}. Saving ${next.label} '
          'removes the ${current.day != null ? 'day' : 'month'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep the saved date'),
          ),
          FilledButton(
            key: const ValueKey<String>('release-date-confirm-less-precise'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Use ${next.label}'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final parsed = _parsed;
    final error = _error;

    return AlertDialog(
      title: const Text('Release date'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('release-studio-date-field'),
            controller: _text,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Date',
              hintText: '2026, 2026-04 or 2026-04-17',
              helperText: 'Only the year, the month, or the exact day.',
              errorText: error,
              suffixIcon: _value.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear the date',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => setState(_text.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('release-date-pick-day'),
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Choose a day'),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('release-date-pick-month'),
                onPressed: _pickMonth,
                icon: const Icon(Icons.date_range_rounded),
                label: const Text('Month or year'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              key: const ValueKey<String>('release-date-preview'),
              _value.isEmpty
                  ? (widget.current == null
                        ? 'No release date.'
                        : 'Saving removes the release date.')
                  : parsed == null
                  ? ''
                  : 'Saves as ${parsed.label}${switch (parsed.precision) {
                      ReleaseDatePrecision.year => ' (year only)',
                      ReleaseDatePrecision.month => ' (month and year)',
                      ReleaseDatePrecision.day => '',
                    }}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('release-studio-save-date'),
          onPressed: error == null ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A year and, optionally, a month: for when the day is not known.
class _MonthYearDialog extends StatefulWidget {
  const _MonthYearDialog({
    required this.initialYear,
    required this.initialMonth,
    required this.firstYear,
    required this.lastYear,
  });

  final int initialYear;
  final int? initialMonth;
  final int firstYear;
  final int lastYear;

  @override
  State<_MonthYearDialog> createState() => _MonthYearDialogState();
}

class _MonthYearDialogState extends State<_MonthYearDialog> {
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late int _year = widget.initialYear.clamp(widget.firstYear, widget.lastYear);

  void _moveYear(int by) => setState(
    () => _year = (_year + by).clamp(widget.firstYear, widget.lastYear),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget step(int by, IconData icon, String tooltip) => IconButton(
      key: ValueKey<String>('release-date-year-$by'),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed:
          (by < 0 && _year > widget.firstYear) ||
              (by > 0 && _year < widget.lastYear)
          ? () => _moveYear(by)
          : null,
    );

    return AlertDialog(
      title: const Text('Month or year'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ten years at a time, then one: any year in a few taps.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              step(
                -10,
                Icons.keyboard_double_arrow_left_rounded,
                '10 years back',
              ),
              step(-1, Icons.chevron_left_rounded, 'Previous year'),
              Semantics(
                liveRegion: true,
                label: 'Year $_year',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$_year',
                    key: const ValueKey<String>('release-date-year'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              step(1, Icons.chevron_right_rounded, 'Next year'),
              step(
                10,
                Icons.keyboard_double_arrow_right_rounded,
                '10 years on',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var month = 1; month <= 12; month++)
                ChoiceChip(
                  key: ValueKey<String>('release-date-month-$month'),
                  label: Text(_months[month - 1]),
                  selected:
                      month == widget.initialMonth &&
                      _year == widget.initialYear,
                  onSelected: (_) =>
                      Navigator.of(context).pop(ReleaseDate.of(_year, month)),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('release-date-year-only'),
          onPressed: () => Navigator.of(context).pop(ReleaseDate.of(_year)),
          child: Text('Only $_year'),
        ),
      ],
    );
  }
}
