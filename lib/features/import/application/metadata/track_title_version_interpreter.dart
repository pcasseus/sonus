import 'package:sonus_next/features/library/domain/entities/song.dart';

class InterpretedTrackTitle {
  const InterpretedTrackTitle({
    required this.title,
    this.versionLabel,
    this.versionCharacteristics = const [],
  });

  final String title;
  final String? versionLabel;
  final List<SongVersionCharacteristic> versionCharacteristics;
}

class TrackTitleVersionInterpreter {
  const TrackTitleVersionInterpreter();

  InterpretedTrackTitle interpret(String rawTitle) {
    final cleaned = rawTitle.trim();

    if (cleaned.isEmpty) {
      return const InterpretedTrackTitle(title: '');
    }

    final match = _terminalQualifierPattern.firstMatch(cleaned);

    if (match == null) {
      return InterpretedTrackTitle(title: cleaned);
    }

    final baseTitle = match.group(1)?.trim() ?? '';
    final qualifier =
        match.group(2)?.trim() ??
        match.group(3)?.trim() ??
        match.group(4)?.trim() ??
        '';

    if (baseTitle.isEmpty || qualifier.isEmpty) {
      return InterpretedTrackTitle(title: cleaned);
    }

    final characteristics = _characteristicsFor(qualifier);

    if (characteristics.isEmpty) {
      return InterpretedTrackTitle(title: cleaned);
    }

    return InterpretedTrackTitle(
      title: baseTitle,
      versionLabel: qualifier,
      versionCharacteristics: List.unmodifiable(characteristics),
    );
  }

  static final RegExp _terminalQualifierPattern = RegExp(
    r'^(.*?)\s*(?:\(([^()]+)\)|\[([^\[\]]+)\]|\s+-\s+(.+))$',
  );

  List<SongVersionCharacteristic> _characteristicsFor(String qualifier) {
    final normalized = qualifier.toLowerCase().trim();
    final result = <SongVersionCharacteristic>[];

    void add(SongVersionCharacteristic value) {
      if (!result.contains(value)) {
        result.add(value);
      }
    }

    if (_containsWord(normalized, 'radio edit')) {
      add(SongVersionCharacteristic.radioEdit);
    }

    if (_containsWord(normalized, 'extended mix') ||
        _containsWord(normalized, 'extended')) {
      add(SongVersionCharacteristic.extended);
    }

    if (_containsWord(normalized, 'remaster')) {
      add(SongVersionCharacteristic.remaster);
    }

    if (_containsWord(normalized, 'instrumental')) {
      add(SongVersionCharacteristic.instrumental);
    }

    if (_containsWord(normalized, 'acoustic')) {
      add(SongVersionCharacteristic.acoustic);
    }

    if (_containsWord(normalized, 'demo')) {
      add(SongVersionCharacteristic.demo);
    }

    if (_containsWord(normalized, 'live')) {
      add(SongVersionCharacteristic.live);
    }

    if (_containsWord(normalized, 'remix')) {
      add(SongVersionCharacteristic.remix);
    }

    if (_containsWord(normalized, 'alternate') ||
        _containsWord(normalized, 'alternative')) {
      add(SongVersionCharacteristic.alternate);
    }

    if (_containsWord(normalized, 'edit') &&
        !result.contains(SongVersionCharacteristic.radioEdit)) {
      add(SongVersionCharacteristic.edit);
    }

    return result;
  }

  bool _containsWord(String value, String phrase) {
    final escaped = RegExp.escape(phrase);

    return RegExp(
      '(^|[^a-z0-9])$escaped([^a-z0-9]|\$)',
      caseSensitive: false,
    ).hasMatch(value);
  }
}
