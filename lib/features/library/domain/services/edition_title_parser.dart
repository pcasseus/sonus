import '../entities/album_edition.dart';

/// An album title split into the base album and an edition qualifier, for
/// example "locket (Deluxe)" into "locket" and deluxe.
class ParsedEditionTitle {
  const ParsedEditionTitle({required this.baseTitle, required this.type});

  final String baseTitle;
  final AlbumEditionType type;
}

/// Recognizes edition qualifiers at the end of an album title.
///
/// Deliberately strict: only a recognized edition phrase, in trailing
/// brackets or after a trailing dash, counts. Other bracketed text, such as
/// "(unless you want it to be)", is part of the title, so albums are never
/// joined on a guess.
class EditionTitleParser {
  const EditionTitleParser._();

  static final RegExp _bracketed = RegExp(
    r'^(.*\S)\s*[\(\[]\s*([^\(\)\[\]]+?)\s*[\)\]]\s*$',
  );
  static final RegExp _dashed = RegExp(r'^(.*\S)\s+[-–—]\s+(.+?)\s*$');

  static final List<(RegExp, AlbumEditionType)> _qualifiers = [
    (
      RegExp(r'^(super\s+)?deluxe(\s+(edition|version))?$'),
      AlbumEditionType.deluxe,
    ),
    (RegExp(r'^expanded(\s+(edition|version))?$'), AlbumEditionType.expanded),
    (
      RegExp(r'^(\d+(st|nd|rd|th)\s+)?anniversary(\s+(edition|version))?$'),
      AlbumEditionType.anniversary,
    ),
    (
      RegExp(r'^(\d{4}\s+)?remaster(ed)?(\s+(\d{4}|edition|version))?$'),
      AlbumEditionType.remaster,
    ),
    (
      RegExp(
        r'^(special|complete|platinum|extended|collector.?s|bonus\s+tracks?)'
        r'(\s+(edition|version))?$',
      ),
      AlbumEditionType.other,
    ),
  ];

  /// The base title and edition type, or null when [albumTitle] carries no
  /// recognized edition qualifier.
  static ParsedEditionTitle? parse(String albumTitle) {
    final title = albumTitle.trim();

    for (final pattern in [_bracketed, _dashed]) {
      final match = pattern.firstMatch(title);

      if (match == null) {
        continue;
      }

      final base = match.group(1)!.trim();
      final qualifier = match
          .group(2)!
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');

      for (final (expression, type) in _qualifiers) {
        if (expression.hasMatch(qualifier) && base.isNotEmpty) {
          return ParsedEditionTitle(baseTitle: base, type: type);
        }
      }
    }

    return null;
  }
}
