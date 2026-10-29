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
