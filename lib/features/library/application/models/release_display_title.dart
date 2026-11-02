import '../../domain/entities/album_edition.dart';

/// The release title shown today: the primary edition's title (SN-50 A-Q3).
///
/// The stored base title stays the release's identity for import matching
/// and search; it is shown only when the edition title is empty or just a
/// type name such as "Deluxe".
String releaseDisplayTitle({
  required String baseTitle,
  required String? editionTitle,
}) {
  final title = editionTitle?.trim() ?? '';

  if (title.isEmpty || isGenericEditionTitle(title)) {
    return baseTitle;
  }

  return title;
}

/// Whether [title] only names an edition type rather than the release.
bool isGenericEditionTitle(String title) {
  return switch (title.trim().toLowerCase()) {
    'standard' ||
    'deluxe' ||
    'expanded' ||
    'anniversary' ||
    'remaster' ||
    'other' => true,
    _ => false,
  };
}

/// The name of an edition type, such as "Deluxe".
String editionTypeLabel(AlbumEditionType type) => switch (type) {
  AlbumEditionType.standard => 'Standard',
  AlbumEditionType.deluxe => 'Deluxe',
  AlbumEditionType.expanded => 'Expanded',
  AlbumEditionType.anniversary => 'Anniversary',
  AlbumEditionType.remaster => 'Remaster',
  AlbumEditionType.other => 'Other',
};

/// The short label naming an edition beside its release title.
///
/// A typed edition shows its type, such as "Deluxe". An Other edition has
/// no type name of its own, so it shows its own name (SN-50 BUG-03): the
/// qualifier when the name is the release title plus one, such as
/// "Remixes" for "Skyline (Remixes)", otherwise the whole name. Only the
/// stored edition title is read; nothing is saved.
String editionLabel({
  required String title,
  required AlbumEditionType type,
  required String baseTitle,
}) {
  final name = title.trim();

  if (name.isNotEmpty && isGenericEditionTitle(name)) {
    return name;
  }

  if (type != AlbumEditionType.other) {
    return editionTypeLabel(type);
  }

  if (name.isEmpty) {
    return editionTypeLabel(type);
  }

  return _qualifierAfter(baseTitle.trim(), name) ?? name;
}

/// "Remixes" from "Skyline (Remixes)", "Skyline [Remixes]" or
/// "Skyline - Remixes" when [base] is "Skyline"; otherwise null.
String? _qualifierAfter(String base, String name) {
  if (base.isEmpty || name.length <= base.length) {
    return null;
  }

  if (name.substring(0, base.length).toLowerCase() != base.toLowerCase()) {
    return null;
  }

  final rest = name.substring(base.length).trim();
  final match =
      RegExp(r'^\((.+)\)$').firstMatch(rest) ??
      RegExp(r'^\[(.+)\]$').firstMatch(rest) ??
      RegExp(r'^[-–—]\s*(.+)$').firstMatch(rest);
  final qualifier = match?.group(1)?.trim() ?? '';

  return qualifier.isEmpty ? null : qualifier;
}
