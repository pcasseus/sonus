import '../../domain/models/cloud_records.dart';
import 'cloud_record_equivalence.dart';
import 'cloud_sync_reader.dart';

typedef FetchCurrentCloudArtist =
    Future<CloudSyncItem?> Function({
      required String userId,
      required String artistId,
    });

/// Decides whether a rejected artist creation can be adopted.
///
/// A conflict result alone is never evidence. The current cloud row is
/// fetched and adopted only when it is owned by the caller, live, at a
/// valid revision and canonically identical to the intended artist. That
/// covers our own creation whose response was lost.
class CloudArtistCreateVerifier {
  const CloudArtistCreateVerifier({required this.fetchCurrentArtist});

  final FetchCurrentCloudArtist fetchCurrentArtist;

  /// Returns the verified cloud revision, or null when nothing may be
  /// adopted.
  Future<int?> adoptableRevision({
    required String userId,
    required CloudArtistRecord artist,
  }) async {
    final current = await fetchCurrentArtist(
      userId: userId,
      artistId: artist.id,
    );

    if (current == null) {
      return null;
    }

    final record = current.record;
    final revision = current.serverRevision;

    if (record is! CloudArtistRecord ||
        record.id != artist.id ||
        record.userId != userId ||
        record.isDeleted ||
        revision == null ||
        revision < 1 ||
        !CloudRecordEquivalence.isEquivalent(record, artist)) {
      return null;
    }

    return revision;
  }
}
