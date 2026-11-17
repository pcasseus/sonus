import '../../../../core/lyrics/lyrics_provenance.dart';

/// The compatibility gate for `lyrics:` cloud archive records (App Update
/// 1.3, database version 48). Client-side only; the server is unchanged.
///
/// Builds before version 48 apply a lyrics record by overwriting the whole
/// row (newest edit wins), drop the provenance columns they do not know,
/// and re-upload what is left. So, until no such client can sync:
///
/// - **Outbound is off** ([uploadsEnabled]): this device uploads no lyrics
///   record and records no lyrics removal. Lyrics already in the cloud stay
///   as they are; nothing is deleted there.
/// - **Inbound is guarded** (`SqliteCloudArchiveStore`): a record without
///   [markerKey] (from an older build) is applied only to a song with no
///   lyrics row or a row with no provenance at all (legacy), and even then
///   it never clears a text. A record carrying the marker is merged text by
///   text with [LyricsPrecedence.replaces], so it can never replace the
///   listener's edit or a better source either. Display-only provider text
///   in any record is ignored.
abstract final class LyricsArchiveSyncGate {
  /// Off until every client that can sync this account understands
  /// provenance. Opening it is a release decision, not a code default.
  static const bool uploadsEnabled = false;

  /// Present (value [provenanceSchema]) in a lyrics payload that carries
  /// provenance. Not a column, so older builds drop it.
  static const String markerKey = 'lyrics_provenance_schema';
  static const int provenanceSchema = 48;

  static bool isMarked(Map<String, Object?> payload) {
    final value = payload[markerKey];
    return value is num && value >= provenanceSchema;
  }

  /// The archive payload for one stored row: display-only text removed,
  /// unset provenance left out (so a legacy row's payload, and fingerprint,
  /// are exactly what earlier builds produced), and the marker added when
  /// any provenance remains. Null when nothing may leave the device.
  static Map<String, Object?>? payloadFor(Map<String, Object?> row) {
    final portable = LyricsRows.hasDisplayOnly(row)
        ? LyricsRows.portable(row)
        : row;
    if (portable == null) return null;
    final payload = <String, Object?>{
      for (final e in portable.entries)
        if (!LyricsColumns.provenance.contains(e.key) ||
            (e.value != null &&
                !(e.key == LyricsColumns.offsetMs && e.value == 0)))
          e.key: e.value,
    };
    if (LyricsRows.hasProvenance(payload)) {
      payload[markerKey] = provenanceSchema;
    }
    return payload;
  }
}
