/// Lyrics provenance rules (App Update 1.3, database version 48).
///
/// Every writer of `track_lyrics` (import rescans, duplicate merge, backup
/// restore, cloud archive apply) decides text by text with
/// [LyricsPrecedence.replaces], so one rule holds everywhere:
///
/// 1. The listener's edit is never replaced by an automatic source. Only
///    another edit at least as recent replaces it.
/// 2. Otherwise a better source is never replaced by a worse one
///    ([LyricsPrecedence.rank]); generated text ranks lowest and is never
///    official.
/// 3. Missing text never erases text (except the listener's own clearing).
library;

/// Where one lyrics text came from. The stored value is [name].
enum LyricsSource {
  /// The listener's own edit.
  user,

  /// A lyrics provider whose licence lets the text be stored.
  provider,

  /// ID3 USLT (plain) or SYLT (synchronised) in the song's own file.
  embedded,

  /// A `.lrc` file next to the song.
  sidecarLrc,

  /// A `.txt` (or other non-`.lrc`) file next to the song.
  sidecarTxt,

  /// Made by Sonus (for example, timing estimated for plain text). Never
  /// official; carries a confidence.
  generated;

  static LyricsSource? fromStored(Object? value) =>
      value is String ? _byName[value] : null;

  static final _byName = {for (final s in values) s.name: s};
}

/// What a provider's licence lets Sonus do with its text.
enum LyricsLicence {
  /// May be stored, backed up and synced.
  cacheable,

  /// May be stored on this device only: never in a backup or the cloud.
  displayOnly,

  /// May only be shown live: never written to the database at all.
  noStore,
}

/// The two texts a song's lyrics row holds.
enum LyricsTextKind {
  plain,
  synced;

  String get textColumn => '${name}_text';
  String get sourceColumn => '${name}_source';
  String get userEditedAtColumn => '${name}_user_edited_at';
  String get updatedAtColumn => '${name}_updated_at';
  String get confidenceColumn => '${name}_confidence';

  /// The columns that travel together when this text is replaced.
  List<String> get columns => [
    textColumn,
    sourceColumn,
    userEditedAtColumn,
    updatedAtColumn,
    confidenceColumn,
  ];
}

/// Row-level column names added in version 48 besides the per-text ones.
abstract final class LyricsColumns {
  static const offsetMs = 'offset_ms';
  static const offsetUserEditedAt = 'offset_user_edited_at';
  static const provider = 'provider';
  static const providerRef = 'provider_ref';
  static const providerLicence = 'provider_licence';
  static const language = 'language';

  static const providerColumns = [provider, providerRef, providerLicence];

  /// Every column that records provenance (none of them is text).
  static final List<String> provenance = [
    for (final kind in LyricsTextKind.values)
      for (final c in kind.columns)
        if (c != kind.textColumn) c,
    offsetMs,
    offsetUserEditedAt,
    ...providerColumns,
    language,
  ];

  static final List<String> all = [
    'song_id',
    for (final kind in LyricsTextKind.values) kind.textColumn,
    'created_at',
    'updated_at',
    ...provenance,
  ];
}

/// One text of a lyrics row with its provenance, read leniently: values a
/// newer or older app might send that this version cannot store are
/// dropped (an unknown source reads as legacy; a user stamp without the
/// user source, or the reverse, reads as not edited).
class LyricsText {
  const LyricsText({
    this.text,
    this.source,
    this.userEditedAt,
    this.updatedAt,
    this.confidence,
  });

  factory LyricsText.fromRow(Map<String, Object?> row, LyricsTextKind kind) {
    final text = row[kind.textColumn];
    var source = LyricsSource.fromStored(row[kind.sourceColumn]);
    final stamp = row[kind.userEditedAtColumn];
    final editedAt = stamp is String ? DateTime.tryParse(stamp) : null;
    final userEdit = source == LyricsSource.user && editedAt != null;
    if (source == LyricsSource.user && !userEdit) source = null;
    final confidence = row[kind.confidenceColumn];
    final updated = row[kind.updatedAtColumn];
    return LyricsText(
      text: text is String ? text : null,
      source: source,
      userEditedAt: userEdit ? editedAt.toUtc() : null,
      updatedAt: updated is String ? updated : null,
      confidence:
          source == LyricsSource.generated &&
              confidence is num &&
              confidence >= 0 &&
              confidence <= 1
          ? confidence.toDouble()
          : null,
    );
  }

  final String? text;

  /// Null: imported before version 48, source not recorded (legacy).
  final LyricsSource? source;
  final DateTime? userEditedAt;
  final String? updatedAt;
  final double? confidence;

  bool get hasText => text?.trim().isNotEmpty ?? false;
  bool get isUserEdit => userEditedAt != null;

  Map<String, Object?> toColumns(LyricsTextKind kind) => {
    kind.textColumn: text,
    kind.sourceColumn: source?.name,
    kind.userEditedAtColumn: userEditedAt?.toIso8601String(),
    kind.updatedAtColumn: updatedAt,
    kind.confidenceColumn: confidence,
  };
}

/// How a writer treats incoming text that ranks the same or better.
enum LyricsMergeMode {
  /// Import rescans and cloud apply: a better or equal source replaces
  /// (an updated sidecar replaces the text it wrote before).
  replaceEqualOrBetter,

  /// Duplicate merge: the kept song's text stays unless it is empty or the
  /// duplicate's is a more recent listener edit.
  keepExisting,
}

abstract final class LyricsPrecedence {
  /// Higher is better. Legacy text (source not recorded) was imported from
  /// a file or synced, so it ranks with the weakest import, above only
  /// generated text: an import that can name its source may replace it,
  /// and generated text never does.
  static int rank(LyricsSource? source) => switch (source) {
    LyricsSource.user => 100,
    LyricsSource.provider => 50,
    LyricsSource.embedded => 40,
    LyricsSource.sidecarLrc => 30,
    LyricsSource.sidecarTxt => 20,
    null => 10,
    LyricsSource.generated => 0,
  };

  /// Whether [incoming] replaces [existing] for one text.
  static bool replaces(
    LyricsText incoming,
    LyricsText existing, {
    LyricsMergeMode mode = LyricsMergeMode.replaceEqualOrBetter,
  }) {
    final existingEdit = existing.userEditedAt;
    if (existingEdit != null) {
      // Rule 1: only a listener edit at least as recent.
      final incomingEdit = incoming.userEditedAt;
      return incomingEdit != null && !incomingEdit.isBefore(existingEdit);
    }
    if (incoming.isUserEdit) return true;
    // Rule 3: nothing never erases something.
    if (!incoming.hasText) return false;
    if (!existing.hasText) return true;
    if (mode == LyricsMergeMode.keepExisting) return false;
    // Rule 2.
    return rank(incoming.source) >= rank(existing.source);
  }
}

/// Row-level merging and the portable (backup, cloud) form of a row.
abstract final class LyricsRows {
  /// Whether the row records anything beyond legacy text.
  static bool hasProvenance(Map<String, Object?> row) {
    for (final column in LyricsColumns.provenance) {
      final value = row[column];
      if (value == null) continue;
      if (column == LyricsColumns.offsetMs && value == 0) continue;
      return true;
    }
    return false;
  }

  /// [row] with every provenance column removed (legacy).
  static Map<String, Object?> withoutProvenance(Map<String, Object?> row) => {
    for (final e in row.entries)
      if (!LyricsColumns.provenance.contains(e.key)) e.key: e.value,
  };

  /// Whether [kind]'s text in [row] is display-only provider text.
  static bool isDisplayOnly(Map<String, Object?> row, LyricsTextKind kind) =>
      row[LyricsColumns.providerLicence] == LyricsLicence.displayOnly.name &&
      row[kind.sourceColumn] == LyricsSource.provider.name;

  static bool hasDisplayOnly(Map<String, Object?> row) =>
      LyricsTextKind.values.any((kind) => isDisplayOnly(row, kind));

  /// [row] with display-only provider text blanked (text and provenance),
  /// as it may leave this device. Null when nothing portable is left.
  static Map<String, Object?>? portable(Map<String, Object?> row) {
    final out = {...row};
    var blanked = false;
    for (final kind in LyricsTextKind.values) {
      if (!isDisplayOnly(row, kind)) continue;
      for (final column in kind.columns) {
        if (out.containsKey(column)) out[column] = null;
      }
      blanked = true;
    }
    if (blanked) {
      final providerLeft = LyricsTextKind.values.any(
        (k) => out[k.sourceColumn] == LyricsSource.provider.name,
      );
      if (!providerLeft) {
        for (final column in [
          ...LyricsColumns.providerColumns,
          LyricsColumns.language,
        ]) {
          if (out.containsKey(column)) out[column] = null;
        }
      }
    }
    final keeps = LyricsTextKind.values.any((k) {
      final t = LyricsText.fromRow(out, k);
      return t.hasText || t.isUserEdit;
    });
    return keeps || out[LyricsColumns.offsetUserEditedAt] != null ? out : null;
  }

  /// Merges [incoming] into [existing] text by text; returns the full row
  /// to store, or null when nothing changes. [stamp] becomes `updated_at`
  /// when something does.
  static Map<String, Object?>? merge({
    required String songId,
    required Map<String, Object?>? existing,
    required Map<String, Object?> incoming,
    required String stamp,
    LyricsMergeMode mode = LyricsMergeMode.replaceEqualOrBetter,
  }) {
    final base = existing ?? const <String, Object?>{};
    final result = <String, Object?>{
      for (final column in LyricsColumns.all) column: base[column],
      'song_id': songId,
    };
    var incomingProvider = false;
    var incomingWon = false;
    for (final kind in LyricsTextKind.values) {
      final from = LyricsText.fromRow(incoming, kind);
      final here = LyricsText.fromRow(base, kind);
      if (LyricsPrecedence.replaces(from, here, mode: mode)) {
        result.addAll(from.toColumns(kind));
        incomingWon = true;
        incomingProvider |= from.source == LyricsSource.provider;
      } else {
        // Kept as stored, byte for byte.
        for (final column in kind.columns) {
          result[column] = base[column];
        }
      }
    }

    // The offset follows rule 1: only a listener correction at least as
    // recent replaces one; automatic writers never send an offset.
    final inOffsetAt = _time(incoming[LyricsColumns.offsetUserEditedAt]);
    final hereOffsetAt = _time(base[LyricsColumns.offsetUserEditedAt]);
    final inOffset = incoming[LyricsColumns.offsetMs];
    if (inOffsetAt != null &&
        inOffset is int &&
        inOffset.abs() <= 600000 &&
        (hereOffsetAt == null || !inOffsetAt.isBefore(hereOffsetAt))) {
      result[LyricsColumns.offsetMs] = inOffset;
      result[LyricsColumns.offsetUserEditedAt] = inOffsetAt.toIso8601String();
    } else if (hereOffsetAt == null) {
      result[LyricsColumns.offsetMs] = null;
      result[LyricsColumns.offsetUserEditedAt] = null;
    }

    // Provider details describe the provider text that is kept.
    if (incomingProvider) {
      for (final c in LyricsColumns.providerColumns) {
        result[c] = incoming[c];
      }
      if (result[LyricsColumns.providerLicence] case final licence?
          when licence != LyricsLicence.cacheable.name &&
              licence != LyricsLicence.displayOnly.name) {
        result[LyricsColumns.providerLicence] = null;
      }
    }
    if (!LyricsTextKind.values.any(
      (k) => result[k.sourceColumn] == LyricsSource.provider.name,
    )) {
      for (final c in LyricsColumns.providerColumns) {
        result[c] = null;
      }
    }
    final language = incoming[LyricsColumns.language];
    if (language is String && (incomingWon || result['language'] == null)) {
      result[LyricsColumns.language] = language;
    }

    if (existing == null) {
      final anything = LyricsTextKind.values.any((k) {
        final t = LyricsText.fromRow(result, k);
        return t.hasText || t.isUserEdit;
      });
      if (!anything && result[LyricsColumns.offsetUserEditedAt] == null) {
        return null;
      }
      final created = incoming['created_at'];
      result['created_at'] = created is String ? created : stamp;
      result['updated_at'] = stamp;
      return result;
    }

    final changed = LyricsColumns.all.any(
      (c) => c != 'updated_at' && result[c] != existing[c],
    );
    if (!changed) return null;
    result['updated_at'] = stamp;
    return result;
  }

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
