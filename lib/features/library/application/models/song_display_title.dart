import '../../domain/entities/song.dart';

/// The label Sonus shows for a version characteristic.
String songVersionCharacteristicLabel(
  SongVersionCharacteristic characteristic,
) {
  return switch (characteristic) {
    SongVersionCharacteristic.remix => 'Remix',
    SongVersionCharacteristic.live => 'Live',
    SongVersionCharacteristic.acoustic => 'Acoustic',
    SongVersionCharacteristic.demo => 'Demo',
    SongVersionCharacteristic.instrumental => 'Instrumental',
    SongVersionCharacteristic.edit => 'Edit',
    SongVersionCharacteristic.radioEdit => 'Radio Edit',
    SongVersionCharacteristic.extended => 'Extended',
    SongVersionCharacteristic.remaster => 'Remaster',
    SongVersionCharacteristic.alternate => 'Alternate',
  };
}

/// Describing words first, so a qualifier reads "Acoustic Remix", and
/// "Radio Edit" before "Edit" so the shorter one is dropped as redundant.
const List<SongVersionCharacteristic> _qualifierOrder = [
  SongVersionCharacteristic.live,
  SongVersionCharacteristic.acoustic,
  SongVersionCharacteristic.instrumental,
  SongVersionCharacteristic.extended,
  SongVersionCharacteristic.alternate,
  SongVersionCharacteristic.demo,
  SongVersionCharacteristic.remaster,
  SongVersionCharacteristic.radioEdit,
  SongVersionCharacteristic.edit,
  SongVersionCharacteristic.remix,
];

/// The song title shown on current surfaces (SN-50 C-Q6/C-Q22): the stored
/// canonical [title] plus one parenthesized version qualifier, as in
/// "Song (Live)" or "Song (Acoustic Remix)".
///
/// The qualifier is the stored [versionLabel] when set; otherwise the
/// [characteristics] labels joined with spaces. Words the title already
/// carries in a bracketed or " - " qualifier are never repeated, compared
/// case-insensitively, so "Song (Live at Wembley)" labelled "Live" stays as
/// it is. Read-time only: nothing stored is rewritten, and frozen snapshots
/// (charts, Moments, listening history) keep their recorded titles.
String songDisplayTitle({
  required String title,
  String? versionLabel,
  List<SongVersionCharacteristic> characteristics = const [],
}) {
  final baseTitle = title.trim();
  final titleQualifiers = _qualifierSegments(baseTitle);
  final label = versionLabel?.trim() ?? '';

  if (label.isNotEmpty) {
    if (_containsPhrase(titleQualifiers, label)) {
      return baseTitle;
    }

    return '$baseTitle ($label)';
  }

  final words = <String>[];

  for (final characteristic in _qualifierOrder) {
    if (!characteristics.contains(characteristic)) {
      continue;
    }

    final characteristicLabel = songVersionCharacteristicLabel(characteristic);

    if (_containsPhrase(titleQualifiers, characteristicLabel) ||
        _containsPhrase([words.join(' ')], characteristicLabel)) {
      continue;
    }

    words.add(characteristicLabel);
  }

  if (words.isEmpty) {
    return baseTitle;
  }

  return '$baseTitle (${words.join(' ')})';
}

final RegExp _bracketed = RegExp(r'[\(\[]([^\)\]]*)[\)\]]');

/// The bracketed parts of [title], and whatever follows a " - ".
List<String> _qualifierSegments(String title) {
  final segments = [
    for (final match in _bracketed.allMatches(title)) match.group(1) ?? '',
  ];
  final dash = title.indexOf(' - ');

  if (dash >= 0) {
    segments.add(title.substring(dash + 3));
  }

  return segments;
}

/// Whether any of [segments] contains [phrase] as whole words.
bool _containsPhrase(List<String> segments, String phrase) {
  final words = _words(phrase);

  if (words.isEmpty) {
    return false;
  }

  for (final segment in segments) {
    final segmentWords = _words(segment);

    for (var start = 0; start + words.length <= segmentWords.length; start++) {
      var matches = true;

      for (var offset = 0; offset < words.length; offset++) {
        if (segmentWords[start + offset] != words[offset]) {
          matches = false;
          break;
        }
      }

      if (matches) {
        return true;
      }
    }
  }

  return false;
}

final RegExp _wordSeparator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String value) {
  return value
      .toLowerCase()
      .split(_wordSeparator)
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
}
