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

/// The one release date editor (App Update 1.2, BUG-10): a year, then an
/// optional month, then an optional day, so a date is saved exactly as
/// precisely as it is known (`2026`, `2026-04` or `2026-04-17`) and an
/// unknown month or day is never invented. A calendar can fill all three.
///
/// The fields are stacked, so nothing overflows at any width or text size.
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

  /// Today, for the range of years; the clock when null.
  final DateTime? today;

  @override
  State<ReleaseDateEditorDialog> createState() =>
      _ReleaseDateEditorDialogState();
}

/// The earliest year the editor accepts.
const int releaseDateFirstYear = 1900;

/// The months, as the month field lists them.
const List<String> releaseDateMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The days [month] has in [year]; with no valid year, February has 29 so
/// that a leap day can still be chosen before the year is typed.
int releaseDateDaysIn(int month, int? year) {
  if (month == 2) {
    if (year == null) return 29;
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  return const [4, 6, 9, 11].contains(month) ? 30 : 31;
}

class _ReleaseDateEditorDialogState extends State<ReleaseDateEditorDialog> {
  late final TextEditingController _year = TextEditingController(
    text: widget.current?.year.toString() ?? '',
  );
  late int? _month = widget.current?.month;
  late int? _day = widget.current?.day;

  /// Why the day was just cleared, shown until the next change.
  String? _dayNotice;

  DateTime get _today => widget.today ?? DateTime.now();

  int get _lastYear => _today.year + 5;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  String get _yearText => _year.text.trim();

  bool get _isEmpty => _yearText.isEmpty && _month == null;

  /// The typed year when it is a usable one.
  int? get _validYear {
    final year = int.tryParse(_yearText);
    if (_yearText.length != 4 || year == null) return null;
    if (year < releaseDateFirstYear || year > _lastYear) return null;
    return year;
  }

  String? get _yearError {
    if (_yearText.isEmpty) {
      return _month == null ? null : 'Enter the year.';
    }
    if (_validYear == null) {
      return 'Use a year from $releaseDateFirstYear to $_lastYear.';
    }
    return null;
  }

  ReleaseDate? get _date {
    final year = _validYear;
    if (year == null) return null;
    return ReleaseDate.of(year, _month, _month == null ? null : _day);
  }

  /// Keeps the day only while the month and year still have it.
  void _fitDay() {
    final day = _day;
    final month = _month;
    if (day == null) return;
    if (month == null) {
      _day = null;
      return;
    }
    final days = releaseDateDaysIn(month, _validYear);
    if (day > days) {
      _day = null;
      final year = _validYear;
      final monthName = releaseDateMonthNames[month - 1];
      _dayNotice =
          'Day cleared: ${year == null ? monthName : '$monthName $year'} '
          'has $days days.';
    }
  }

  void _setMonth(int? month) => setState(() {
    _dayNotice = null;
    _month = month;
    _fitDay();
  });

  void _setDay(int? day) => setState(() {
    _dayNotice = null;
    _day = day;
  });

  void _yearChanged() => setState(() {
    _dayNotice = null;
    _fitDay();
  });

  void _clearAll() => setState(() {
    _dayNotice = null;
    _year.clear();
    _month = null;
    _day = null;
  });

  /// The calendar opens at the date being edited, or today.
  DateTime get _calendarStart {
    final date = _date ?? widget.current;
    if (date == null) return _today;
    final start = DateTime(date.year, date.month ?? 1, date.day ?? 1);
    final last = DateTime(_lastYear, 12, 31);
    return start.isAfter(last) ? last : start;
  }

  Future<void> _pickOnCalendar() async {
    final date = _date ?? widget.current;
    final picked = await showDatePicker(
      context: context,
      initialDate: _calendarStart,
      firstDate: DateTime(releaseDateFirstYear),
      lastDate: DateTime(_lastYear, 12, 31),
      // Without a day to start from, open on the year grid so any year is
      // a scroll and a tap away.
      initialDatePickerMode: date?.day == null
          ? DatePickerMode.year
          : DatePickerMode.day,
      helpText: 'Release day',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dayNotice = null;
      _year.text = '${picked.year}';
      _month = picked.month;
      _day = picked.day;
    });
  }

  bool get _canSave => _isEmpty || (_yearError == null && _date != null);

  Future<void> _save() async {
    if (!_canSave) return;
    if (_isEmpty) {
      Navigator.of(context).pop(const ReleaseDateCleared());
      return;
    }
    final date = _date!;

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
          'removes the ${_removedDetail(current, next)}.',
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

  /// What saving [next] over [current] removes.
  static String _removedDetail(ReleaseDate current, ReleaseDate next) {
    if (current.day == null) return 'month';
    return next.month == null ? 'month and day' : 'day';
  }

  String get _preview {
    if (_isEmpty) {
      return widget.current == null
          ? 'No release date.'
          : 'Saving removes the release date.';
    }
    final date = _date;
    if (date == null) return '';
    return 'Saves as ${date.label}${switch (date.precision) {
      ReleaseDatePrecision.year => ' (year only)',
      ReleaseDatePrecision.month => ' (month and year)',
      ReleaseDatePrecision.day => '',
    }}.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final month = _month;
    final days = month == null ? 0 : releaseDateDaysIn(month, _validYear);

    return AlertDialog(
      title: const Text('Release date'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey<String>('release-date-year-field'),
            controller: _year,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: 'Year',
              hintText: '${_today.year}',
              errorText: _yearError,
              errorMaxLines: 3,
            ),
            onChanged: (_) => _yearChanged(),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: const ValueKey<String>('release-date-month'),
            initialValue: month,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Month (optional)'),
            items: [
              const DropdownMenuItem<int?>(
                key: ValueKey<String>('release-date-month-item-none'),
                child: Text('Unknown'),
              ),
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem<int?>(
                  key: ValueKey<String>('release-date-month-item-$m'),
                  value: m,
                  child: Text(releaseDateMonthNames[m - 1]),
                ),
            ],
            onChanged: _setMonth,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            // Rebuilt when the month or the number of days changes, so it
            // never holds a day the month does not have.
            key: ValueKey<String>('release-date-day-$month-$days'),
            initialValue: month == null ? null : _day,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Day (optional)',
              helperText: month == null ? 'Choose a month first.' : null,
              helperMaxLines: 2,
            ),
            items: [
              const DropdownMenuItem<int?>(
                key: ValueKey<String>('release-date-day-item-none'),
                child: Text('Unknown'),
              ),
              for (var d = 1; d <= days; d++)
                DropdownMenuItem<int?>(
                  key: ValueKey<String>('release-date-day-item-$d'),
                  value: d,
                  child: Text('$d'),
                ),
            ],
            onChanged: month == null ? null : _setDay,
          ),
          if (_dayNotice case final notice?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                notice,
                key: const ValueKey<String>('release-date-day-notice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: const ValueKey<String>('release-date-pick-day'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _pickOnCalendar,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Pick on calendar'),
              ),
              if (!_isEmpty)
                TextButton.icon(
                  key: const ValueKey<String>('release-date-remove'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Remove date'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              key: const ValueKey<String>('release-date-preview'),
              _preview,
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
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
